import {
  ROUND_LIMITS,
  traySettings,
  validateGrouping
} from './policies.js';
import * as Space from './spatial.js';
import { resolvePose } from './poses.js';

const copy = value => structuredClone(value);
const blankBay = available => ({
  available,
  group: -1,
  required: 0,
  filled: 0,
  sequence: 0
});
const within = (value, low, high) => Number.isInteger(value) && value >= low && value <= high;
const hashSpec = value => {
  let checksum = 2166136261;
  for (const letter of JSON.stringify(value)) checksum = Math.imul(checksum ^ letter.charCodeAt(0), 16777619);
  return checksum >>> 0;
};

export class SortingSession {
  #tokens;
  #schedule;
  #neighbors = new Map();
  #binding;
  #options;
  #model;
  #signals = [];
  #listener;

  constructor(stage, forms, options = {}) {
    const profile = {
      bays: 3,
      trayMode: 'flexible',
      prompts: true,
      promptPolicy: 'classic',
      combinedPicks: false,
      ...options
    };
    if (![3, 4].includes(profile.bays)) throw new RangeError('Invalid bay capacity');
    const trayPolicy = traySettings(profile.trayMode);
    if (profile.grouping !== undefined && !validateGrouping(profile.grouping)) throw new TypeError('Invalid grouping');
    const translations = new Map(profile.grouping?.pairs ?? []);
    const groupOf = id => translations.get(id) ?? id;
    this.#listener = profile.onSignal;
    delete profile.onSignal;
    this.#options = copy(profile);
    this.#binding = hashSpec(stage);
    this.#tokens = stage.specimens.map((placement, tokenId) => {
      const form = forms[placement.form];
      if (!form) throw new RangeError(`Missing form: ${placement.form}`);
      placement=resolvePose(placement,form,tokenId);
      const contour = Space.composeOutline(form, placement);
      return {
        tokenId,
        form: placement.form,
        group: groupOf(placement.group),
        contour,
        bounds: Space.rectangularEnvelope(form.extent, placement),
        placement
      };
    });
    this.#schedule = stage.shipments.map((entry, i) => ({
      group: groupOf(entry.group),
      required: entry.quantity,
      sequence: i + 1
    }));
    this.#model = {
      phase: 'live',
      seconds: 0,
      board: this.#tokens.map(token => token.tokenId),
      cursor: 0,
      bays: Array.from({
        length: profile.bays
      }, (_, i) => blankBay(i < ROUND_LIMITS.initialRequests)),
      tray: Array.from({
        length: trayPolicy.places
      }, (_, i) => ({
        available: i < trayPolicy.available,
        tokenId: null
      })),
      advanceCredits: {},
      advanceTracked: false,
      warningShown: false,
      promptRemaining: ROUND_LIMITS.idlePrompts,
      quietSeconds: 0,
      promptToken: null,
      promptPaused: false,
      arrivalKnown: true,
      arrival: [],
      reversals: [],
      scanRemaining: 0,
      scanTracked: false,
      scanTokens: [],
    };
    for (let bay = 0; bay < profile.bays; bay++)
      if (this.#model.bays[bay].available && this.#model.cursor < this.#schedule.length) this.#loadBay(bay, false);
  }

  inspect() {
    return copy(this.#model);
  }
  takeSignals() {
    const batch = this.#signals;
    this.#signals = [];
    return batch;
  }
  get settings() {
    return copy(this.#options);
  }
  get binding() {
    return this.#binding;
  }
  get visibleBays() {
    return this.#options.bays === 4 && this.#model.bays[2].available ? 4 : 3;
  }
  get canContinue() {
    return this.#model.phase === 'lost' && this.#model.tray.some(cell => !cell.available);
  }
  tokenInfo(tokenId) {
    const token = this.#tokens[tokenId];
    return token ? {
      ...copy(token.placement),
      tokenId,
      form: token.form,
      group: token.group,
      bounds: {
        ...token.bounds
      }
    } : null;
  }
  #announce(kind, detail = {}, context) {
    const signal = {
      kind,
      ...detail
    };
    this.#signals.push(signal);
    this.#listener?.(copy(signal), context);
  }
  #dismissPrompt(reset = true) {
    const state = this.#model;
    if (reset) state.quietSeconds = 0;
    if (state.promptToken !== null) {
      this.#announce('promptDismissed', {
        tokenId: state.promptToken
      });
      state.promptToken = null;
    }
  }
  #dropScan(tokenId) {
    const list = this.#model.scanTokens;
    if (!list.includes(tokenId)) return;
    list.splice(list.indexOf(tokenId), 1);
    this.#announce('scanRemoved', {
      tokenId
    });
  }
  #destination(group) {
    let chosen = -1;
    this.#model.bays.forEach((bay, index) => {
      if (bay.available && bay.group === group && bay.filled < bay.required && (chosen < 0 || bay.filled > this.#model.bays[chosen].filled)) chosen = index;
    });
    return chosen;
  }
  #occluders(tokenId) {
    if (!this.#neighbors.has(tokenId)) {
      const token = this.#tokens[tokenId];
      const candidates = this.#tokens.slice(tokenId + 1).filter(other =>
        Space.boxesMeet(token.bounds, other.bounds) && Space.contoursMeet(token.contour, other.contour) &&
        Space.coverageFraction(token.contour, [other.contour]) >= ROUND_LIMITS.contactFraction);
      this.#neighbors.set(tokenId, candidates.map(other => other.tokenId));
    }
    return this.#neighbors.get(tokenId);
  }
  isObstructed(tokenId) {
    const remaining = new Set(this.#model.board);
    const above = this.#occluders(tokenId).filter(id => remaining.has(id)).map(id => this.#tokens[id].contour);
    return above.length > 0 && Space.coverageFraction(this.#tokens[tokenId].contour, above, ROUND_LIMITS.exactOccluders) >= ROUND_LIMITS.obstructionFraction;
  }
  #hasImmediateMove() {
    return this.#model.board.some(id => this.#destination(this.#tokens[id].group) >= 0 && !this.isObstructed(id));
  }
  #loadBay(index, announce = true) {
    const state = this.#model,
      shipment = this.#schedule[state.cursor++],
      bay = state.bays[index];
    Object.assign(bay, shipment, {
      filled: state.advanceCredits[shipment.sequence] ?? 0
    });
    delete state.advanceCredits[shipment.sequence];
    if (announce) this.#announce('bayAssigned', {
      bay: index,
      shipment: copy(bay)
    });
    if (bay.filled === bay.required) this.#finishBay(index);
  }
  #finishBay(index) {
    const state = this.#model;
    this.#announce('bayCompleted', {
      bay: index
    });
    if (state.cursor < this.#schedule.length) {
      this.#loadBay(index);
      this.#feedBay(index);
      return;
    }
    Object.assign(state.bays[index], blankBay(state.bays[index].available));
    this.#announce('bayVacated', {
      bay: index
    });
    if (state.bays.every(bay => bay.group === -1)) {
      state.phase = 'done';
      this.#dismissPrompt();
      this.#announce('roundCleared', {
        seconds: state.seconds
      });
    }
  }
  #feedBay(index) {
    const state = this.#model,
      bay = state.bays[index];
    if (bay.group === -1) return;
    for (let cell = 0; cell < state.tray.length; cell++) {
      const id = state.tray[cell].tokenId;
      if (id === null || this.#tokens[id].group !== bay.group || bay.filled >= bay.required) continue;
      state.tray[cell].tokenId = null;
      state.reversals = state.reversals.filter(value => value !== id);
      bay.filled++;
      this.#announce('trayDelivered', {
        tokenId: id,
        cell,
        bay: index,
        filled: bay.filled
      });
    }
    if (bay.filled === bay.required) this.#finishBay(index);
  }
  #lose(bay = null, rejected = null, avoidable, notice = false) {
    this.#model.phase = 'lost';
    this.#dismissPrompt();
    this.#announce('roundLost', {
      ...(notice ? {
        notice: true
      } : {}),
      ...(bay !== null ? {
        bay
      } : {}),
      ...(rejected !== null ? {
        rejected
      } : {})
    }, avoidable);
  }
  #assessTray(bay = null) {
    const state = this.#model;
    if (state.phase !== 'live') return;
    const capacity = state.tray.filter(cell => cell.available).length,
      occupied = state.tray.filter(cell => cell.tokenId !== null).length;
    if (!state.warningShown && occupied === capacity - 1) {
      state.warningShown = true;
      this.#announce('trayNearlyFull', {
        cell: state.tray.findIndex(cell => cell.available && cell.tokenId === null)
      });
      return;
    }
    const policy = traySettings(this.#options.trayMode);
    if (occupied >= capacity && (policy.immediateLoss || !this.#hasImmediateMove())) this.#lose(bay, null, undefined, policy.notice);
  }
  #select(tokenId) {
    const state = this.#model;
    if (state.phase !== 'live' || !state.board.includes(tokenId)) return;
    this.#dismissPrompt();
    if (this.isObstructed(tokenId)) {
      this.#announce('selectionBlocked', {
        tokenId
      });
      return;
    }
    const bayIndex = this.#destination(this.#tokens[tokenId].group);
    if (bayIndex < 0) {
      const avoidable = this.#listener && !this.#options.combinedPicks ? this.#hasImmediateMove() : undefined;
      const cell = state.tray.findIndex(entry => entry.available && entry.tokenId === null);
      if (cell < 0) {
        this.#lose(null, tokenId, avoidable);
        return;
      }
      state.board.splice(state.board.indexOf(tokenId), 1);
      if (state.scanRemaining > 0 && state.scanTokens.includes(tokenId)) state.scanRemaining--;
      this.#dropScan(tokenId);
      state.tray[cell].tokenId = tokenId;
      if (!state.arrivalKnown) state.arrivalKnown = state.tray.filter(entry => entry.tokenId !== null).length === 1;
      state.arrival = state.arrival.filter(id => id !== tokenId && state.tray.some(entry => entry.tokenId === id));
      state.arrival.push(tokenId);
      state.reversals.push(tokenId);
      this.#announce('trayStored', {
        tokenId,
        cell
      }, avoidable);
      this.#settleGroups();
      this.#assessTray();
      this.#refreshScan();
      return;
    }
    state.board.splice(state.board.indexOf(tokenId), 1);
    if (state.scanRemaining > 0 && state.scanTokens.includes(tokenId)) state.scanRemaining--;
    this.#dropScan(tokenId);
    state.reversals = [];
    const bay = state.bays[bayIndex];
    bay.filled++;
    this.#announce('boardDelivered', {
      tokenId,
      bay: bayIndex,
      filled: bay.filled
    });
    if (bay.filled === bay.required) this.#finishBay(bayIndex);
    this.#settleGroups();
    this.#assessTray(bayIndex);
    this.#refreshScan();
  }
  #settleGroups() {
    if (!this.#options.grouping || this.#model.phase !== 'live') return false;
    const state = this.#model,
      before = state.tray.filter(cell => cell.tokenId !== null).length;
    for (const cell of state.tray) {
      if (cell.tokenId === null) continue;
      const destination = this.#destination(this.#tokens[cell.tokenId].group);
      if (destination >= 0) this.#feedBay(destination);
    }
    return state.tray.filter(cell => cell.tokenId !== null).length !== before;
  }
  locate(point, radius = 0, preference = 'nearest') {
    if (this.#model.phase !== 'live') return null;
    const reversed = [...this.#model.board].reverse();
    let exact = reversed.find(id => Space.containsPoint(point, this.#tokens[id].contour));
    if (!(radius > 0)) return exact ?? null;
    // A direct tap must keep the visible object, even when it is obstructed.
    // Touch tolerance is only used when the pointer misses every contour.
    if (exact !== undefined && preference === 'visible') return exact;
    const eligible = this.#model.board.map(id => ({
        id,
        distance: Space.distanceFromContour(point, this.#tokens[id].contour)
      }))
      .filter(entry => entry.distance <= radius).sort((a, b) => a.distance - b.distance || b.id - a.id);
    const available = entry => !this.isObstructed(entry.id);
    if (exact === undefined && preference === 'requested') {
      const preferred = eligible.find(entry => this.#destination(this.#tokens[entry.id].group) >= 0 && available(entry));
      if (preferred) return preferred.id;
    }
    if (exact !== undefined && this.#destination(this.#tokens[exact].group) >= 0 && this.isObstructed(exact)) {
      const top = reversed.find(id => eligible.some(entry => entry.id === id) && !this.isObstructed(id));
      if (top !== undefined && this.#destination(this.#tokens[top].group) >= 0) exact = top;
    } else if (exact === undefined || this.isObstructed(exact)) {
      const nearest = eligible.find(available);
      if (nearest) exact = nearest.id;
    }
    return exact ?? null;
  }
  locateErase(point) {
    return [...this.#model.board].reverse().find(id => Space.distanceFromContour(point, this.#tokens[id].contour) === 0) ?? null;
  }
  #expandBay(target) {
    const state = this.#model,
      index = state.bays.findIndex(bay => !bay.available);
    if (state.phase !== 'live' || index < 0 || index >= this.visibleBays || (target !== undefined && target !== null && target !== index) || (index === 3 && state.cursor >= this.#schedule.length)) return false;
    state.bays[index].available = true;
    this.#announce('bayExpanded', {
      bay: index
    });
    if (state.cursor < this.#schedule.length) {
      this.#loadBay(index);
      this.#feedBay(index);
    }
    this.#assessTray();
    this.#refreshScan();
    return true;
  }
  #expandTray() {
    const state = this.#model,
      cell = state.tray.findIndex(entry => !entry.available);
    if (!['live', 'lost'].includes(state.phase) || cell < 0) return false;
    const continued = state.phase === 'lost';
    state.tray[cell].available = true;
    state.phase = 'live';
    this.#announce('trayExpanded', {
      cell,
      continued
    });
    this.#refreshScan();
    return true;
  }
  preferredBay() {
    let best = -1;
    this.#model.bays.forEach((bay, i) => {
      if (bay.available && bay.group !== -1 && bay.filled < bay.required && (best < 0 || bay.filled > this.#model.bays[best].filled)) best = i;
    });
    return best;
  }
  #sweep(target) {
    const state = this.#model;
    if (state.phase !== 'live') return false;
    const requested = target && state.bays[target.bay];
    const valid = requested && requested.available && requested.group !== -1 && requested.filled < requested.required && (target.sequence == null || target.sequence === requested.sequence);
    const index = valid ? target.bay : this.preferredBay();
    if (index < 0) return false;
    const bay = state.bays[index];
    let moved = 0;
    for (const id of [...state.board].reverse()) {
      if (bay.filled >= bay.required) break;
      if (this.#tokens[id].group !== bay.group) continue;
      if (state.promptToken === id) this.#dismissPrompt();
      state.board.splice(state.board.indexOf(id), 1);
      this.#dropScan(id);
      bay.filled++;
      moved++;
      this.#announce('boardDelivered', {
        tokenId: id,
        bay: index,
        filled: bay.filled,
        assisted: true
      });
    }
    if (!moved) return false;
    if (bay.filled === bay.required) this.#finishBay(index);
    this.#assessTray(index);
    this.#refreshScan();
    return true;
  }
  #erase(tokenId) {
    const state = this.#model;
    if (state.phase !== 'live' || !state.board.includes(tokenId)) return false;
    const group = this.#tokens[tokenId].group,
      index = this.#destination(group);
    const future = index < 0 ? this.#schedule.slice(state.cursor).find(entry => entry.group === group && (state.advanceCredits[entry.sequence] ?? 0) < entry.required) : null;
    if (index < 0 && !future) return false;
    state.board.splice(state.board.indexOf(tokenId), 1);
    state.advanceTracked = true;
    this.#dismissPrompt();
    this.#dropScan(tokenId);
    state.reversals = [];
    this.#announce('tokenErased', {
      tokenId
    });
    if (index >= 0) {
      const bay = state.bays[index];
      bay.filled++;
      this.#announce('eraseDelivered', {
        bay: index,
        filled: bay.filled
      });
      if (bay.filled === bay.required) this.#finishBay(index);
      this.#assessTray(index);
    } else state.advanceCredits[future.sequence] = (state.advanceCredits[future.sequence] ?? 0) + 1;
    this.#refreshScan();
    return true;
  }
  #replaceOnBoard(id) {
    this.#model.board.push(id);
    this.#model.board.sort((a, b) => a - b);
  }
  #reverse() {
    const state = this.#model,
      tokenId = state.reversals.at(-1);
    const cell = state.tray.findIndex(entry => entry.tokenId === tokenId);
    if (state.phase !== 'live' || tokenId === undefined || cell < 0) return false;
    state.reversals.pop();
    state.tray[cell].tokenId = null;
    this.#replaceOnBoard(tokenId);
    this.#dismissPrompt();
    this.#announce('selectionReversed', {
      tokenId,
      cell
    });
    return true;
  }
  latestTrayTokens(quantity = 3) {
    const state = this.#model;
    if (!state.arrivalKnown || !Number.isInteger(quantity) || quantity < 1) return [];
    const occupied = state.tray.filter(cell => cell.tokenId !== null).map(cell => cell.tokenId);
    const arrival = state.arrival.filter(id => occupied.includes(id));
    return [...occupied.filter(id => !arrival.includes(id)), ...arrival].slice(-quantity).reverse();
  }
  #returnTokens(ids, allowEmpty = false) {
    const state = this.#model;
    if (!['live', 'lost'].includes(state.phase) || !state.tray.some(cell => cell.tokenId !== null)) return false;
    if (!Array.isArray(ids) || (!ids.length && !allowEmpty) || new Set(ids).size !== ids.length || !ids.every(id => state.tray.some(cell => cell.tokenId === id))) return false;
    const continued = state.phase === 'lost',
      movements = [];
    for (const tokenId of ids) {
      const cell = state.tray.findIndex(entry => entry.tokenId === tokenId);
      state.tray[cell].tokenId = null;
      state.reversals = state.reversals.filter(id => id !== tokenId);
      this.#replaceOnBoard(tokenId);
      movements.push({
        tokenId,
        cell
      });
    }
    state.phase = 'live';
    this.#dismissPrompt();
    this.#announce('trayReturned', {
      movements,
      continued
    });
    this.#refreshScan();
    return true;
  }
  #choosePrompt() {
    if (this.#options.promptPolicy === 'reachable' && this.#model.phase !== 'live') return null;
    const state = this.#model,
      requested = state.bays.filter(bay => bay.group !== -1 && bay.filled < bay.required && (this.#options.promptPolicy !== 'reachable' || bay.available)).map(bay => bay.group);
    const candidates = requested.flatMap(group => [...state.board].reverse().filter(id => this.#tokens[id].group === group));
    const free = candidates.find(id => !this.isObstructed(id));
    if (free !== undefined) return free;
    if (this.#options.promptPolicy !== 'reachable') return candidates[0] ?? null;
    if (state.phase !== 'live') return null;
    const present = new Set(state.board);
    let allowance = state.tray.filter(cell => cell.available && cell.tokenId === null).length + 1,
      chosen = null;
    if (allowance === 1) return null;
    for (const id of candidates) {
      const blockers = new Set(),
        frontier = [id];
      while (frontier.length && blockers.size < allowance) {
        for (const above of this.#occluders(frontier.pop())) {
          if (!present.has(above) || blockers.has(above)) continue;
          blockers.add(above);
          frontier.push(above);
          if (blockers.size >= allowance) break;
        }
      }
      if (blockers.size < allowance) {
        allowance = blockers.size;
        chosen = id;
      }
    }
    return chosen;
  }
  #prompt() {
    this.#dismissPrompt(false);
    const chosen = this.#choosePrompt();
    if (chosen !== null) {
      this.#model.promptToken = chosen;
      this.#announce('promptShown', {
        tokenId: chosen
      });
    }
  }
  #advance(seconds) {
    const state = this.#model;
    if (state.phase !== 'live') return;
    if (!Number.isFinite(seconds) || seconds < 0) throw new RangeError('Invalid elapsed duration');
    state.seconds += seconds;
    if (!this.#options.prompts || state.promptRemaining <= 0 || state.promptToken !== null || state.promptPaused || state.scanTokens.length) return;
    state.quietSeconds += seconds;
    if (state.quietSeconds >= ROUND_LIMITS.idleSeconds) {
      state.quietSeconds = 0;
      state.promptRemaining--;
      this.#prompt();
    }
  }
  scanChoices(view = null) {
    const state = this.#model;
    if (state.phase !== 'live') return [];
    const needs = new Map();
    for (const bay of state.bays)
      if (bay.available && bay.group !== -1 && bay.filled < bay.required) needs.set(bay.group, (needs.get(bay.group) ?? 0) + bay.required - bay.filled);
    const visible = id => view && Space.boxesMeet(this.#tokens[id].bounds, view) ? 1 : 0;
    const eligible = [...state.board].reverse().filter(id => (needs.get(this.#tokens[id].group) ?? 0) > 0 && !this.isObstructed(id));
    eligible.sort((a, b) => visible(b) - visible(a));
    const selected = [];
    for (const id of eligible) {
      if (selected.length >= ROUND_LIMITS.scanCapacity) break;
      const group = this.#tokens[id].group;
      if (needs.get(group) > 0) {
        needs.set(group, needs.get(group) - 1);
        selected.push(id);
      }
    }
    return selected;
  }
  #refreshScan(view = null, initial = false) {
    const state = this.#model;
    if (state.scanCredits !== undefined) {
      for (const id of [...state.scanTokens])
        if (state.phase !== 'live' || !state.board.includes(id) || this.isObstructed(id) || this.#destination(this.#tokens[id].group) < 0) this.#dropScan(id);
      return state.scanTokens.length > 0;
    }
    if (state.scanRemaining > 0) state.scanTracked = true;
    const next = state.scanRemaining > 0 ? this.scanChoices(view).slice(0, state.scanRemaining) : [];
    for (const id of [...state.scanTokens])
      if (!next.includes(id)) this.#dropScan(id);
    const added = next.some(id => !state.scanTokens.includes(id));
    state.scanTokens = next;
    if (next.length) this.#dismissPrompt();
    if (added) this.#announce('scanHighlighted', {
      tokenIds: [...next],
      ...(initial ? {
        initial: true
      } : {})
    });
    return next.length > 0;
  }
  #grantScan(quantity = 3) {
    if (![1, 3].includes(quantity)) throw new RangeError('Invalid scan grant');
    const state = this.#model;
    if (state.phase !== 'live' || (state.scanCredits ?? state.scanRemaining) > 0 || state.scanTokens.length) return false;
    state.scanCredits = quantity;
    this.#announce('scanCredited');
    return true;
  }
  #activateScan(view) {
    const state = this.#model;
    if (state.phase !== 'live') return 'unavailable';
    this.#refreshScan(view);
    if (state.scanTokens.length) {
      this.#announce('scanFocused', {
        tokenIds: [...state.scanTokens]
      });
      return 'refocus';
    }
    const chosen = this.scanChoices(view)[0];
    if (chosen === undefined) return 'unavailable';
    if (!(state.scanCredits > 0)) return 'empty';
    state.scanCredits--;
    state.scanTokens = [chosen];
    this.#dismissPrompt();
    this.#announce('scanHighlighted', {
      tokenIds: [chosen]
    });
    this.#announce('scanFocused', {
      tokenIds: [chosen]
    });
    return 'activated';
  }
  dispatch(action) {
    const state = this.#model;
    switch (action.kind) {
      case 'collect':
        return this.#select(action.tokenId);
      case 'pointer': {
        const id = this.locate(action.point, action.radius, action.preference);
        if (this.#listener && state.phase === 'live') this.#listener({
          kind: 'pointerObserved',
          point: [...action.point],
          tokenId: id,
          group: id === null ? null : this.#tokens[id].group
        });
        if (id !== null) this.#select(id);
        return id;
      }
      case 'assistedPointer': {
        const assisted = this.locate(action.point, action.radius),
          exact = this.locate(action.point);
        if (assisted !== exact) action.onDifference?.();
        return this.dispatch({
          kind: 'pointer',
          point: action.point,
          radius: action.enabled ? action.radius : 0
        });
      }
      case 'blankPointer': {
        if (state.phase !== 'live') return null;
        const exact = this.locate(action.point);
        if (exact === null && action.radius > 0 && this.locate(action.point, action.radius) !== this.locate(action.point, action.radius, 'requested')) action.onDifference?.();
        return this.dispatch({
          kind: 'pointer',
          point: action.point,
          radius: action.radius,
          preference: exact === null ? action.preference : 'nearest'
        });
      }
      case 'advance':
        return this.#advance(action.seconds);
      case 'expandBay':
        return this.#expandBay(action.bay);
      case 'expandTray':
        return this.#expandTray();
      case 'sweepBay':
        return this.#sweep(action.target);
      case 'erase':
        return this.#erase(action.tokenId);
      case 'reverse':
        return this.#reverse();
      case 'returnTray': {
        if (action.tokenIds) return this.#returnTokens(action.tokenIds);
        const ids = state.tray.filter(cell => cell.tokenId !== null).filter((_, i) => i < (action.quantity ?? ROUND_LIMITS.returnBatch)).map(cell => cell.tokenId);
        return this.#returnTokens(ids, true);
      }
      case 'prompt':
        return this.#prompt();
      case 'pausePrompts':
        state.promptPaused = !!action.paused;
        return;
      case 'scanGrant':
        return this.#grantScan(action.quantity);
      case 'scanActivate':
        return this.#activateScan(action.view);
      case 'scanLegacy':
        if (state.phase !== 'live' || state.scanRemaining > 0) return false;
        state.scanTracked = true;
        state.scanRemaining = ROUND_LIMITS.scanCapacity;
        this.#refreshScan(action.view, true);
        return true;
      case 'scanRefresh':
        return this.#refreshScan(action.view, action.initial);
      case 'scanFocus':
        if (state.scanCredits !== undefined) {
          if (!this.#refreshScan(action.view)) return false;
        } else {
          if (!state.scanRemaining) return false;
          this.#refreshScan(action.view);
        }
        this.#announce('scanFocused', {
          tokenIds: [...state.scanTokens]
        });
        return true;
      case 'settleGroups':
        return this.#settleGroups();
      default:
        throw new RangeError(`Unknown command: ${action.kind}`);
    }
  }
  save() {
    const model = copy(this.#model);
    if (model.arrivalKnown) model.arrival = model.arrival.filter(id => model.tray.some(cell => cell.tokenId === id));
    return {
      schema: 1,
      binding: this.#binding,
      settings: this.settings,
      model
    };
  }
  static resume(stage, forms, saved, options = {}) {
    const ensure = (condition, issue) => {
      if (!condition) throw new TypeError(`Invalid checkpoint: ${issue}`);
    };
    ensure(saved && saved.schema === 1 && saved.settings && saved.model, 'format');
    const instance = new SortingSession(stage, forms, {
        ...saved.settings,
        ...options
      }),
      s = copy(saved.model);
    ensure(saved.binding === instance.#binding, 'stage binding');
    ensure(['live', 'lost', 'done'].includes(s.phase) && Number.isFinite(s.seconds) && s.seconds >= 0, 'round state');
    const validId = id => within(id, 0, instance.#tokens.length - 1);
    ensure(['arrivalKnown', 'warningShown', 'promptPaused', 'advanceTracked', 'scanTracked'].every(key => typeof s[key] === 'boolean'), 'state flags');
    ensure(Array.isArray(s.board) && s.board.every((id, i) => validId(id) && (i === 0 || id > s.board[i - 1])), 'board order');
    ensure(within(s.cursor, 0, instance.#schedule.length) && Array.isArray(s.bays) && s.bays.length === instance.#options.bays, 'schedule');
    const active = new Set();
    s.bays.forEach((bay, i) => {
      ensure(typeof bay.available === 'boolean' && (i >= ROUND_LIMITS.initialRequests || bay.available) && (!bay.available || i === 0 || s.bays[i - 1].available), 'bay access');
      ensure(Number.isInteger(bay.required) && within(bay.filled, 0, bay.required), 'bay amount');
      if (bay.group === -1) ensure(bay.required === 0 && bay.filled === 0 && bay.sequence === 0, 'empty bay');
      else {
        const shipment = instance.#schedule[bay.sequence - 1];
        ensure(bay.available && shipment && shipment.group === bay.group && shipment.required === bay.required && bay.filled < bay.required && bay.sequence <= s.cursor && !active.has(bay.sequence), 'active shipment');
        active.add(bay.sequence);
      }
    });
    const policy = traySettings(instance.#options.trayMode),
      present = new Set(s.board);
    ensure(Array.isArray(s.tray) && s.tray.length === policy.places, 'tray capacity');
    s.tray.forEach((cell, i) => {
      ensure(typeof cell.available === 'boolean' && (i >= policy.available || cell.available), 'tray access');
      ensure(cell.tokenId === null || (cell.available && validId(cell.tokenId) && !present.has(cell.tokenId)), 'tray token');
      if (cell.tokenId !== null) present.add(cell.tokenId);
    });
    ensure(s.advanceCredits && typeof s.advanceCredits === 'object' && !Array.isArray(s.advanceCredits), 'advance credits');
    for (const [sequence, quantity] of Object.entries(s.advanceCredits)) {
      const shipment = instance.#schedule[Number(sequence) - 1];
      ensure(String(Number(sequence)) === sequence && shipment && shipment.sequence > s.cursor && within(quantity, 1, shipment.required), 'future shipment');
    }
    const balance = new Map();
    for (const token of instance.#tokens) balance.set(token.group, (balance.get(token.group) ?? 0) + 1);
    const subtract = (group, n) => balance.set(group, (balance.get(group) ?? 0) - n);
    for (const id of present) subtract(instance.#tokens[id].group, 1);
    for (const shipment of instance.#schedule.slice(0, s.cursor)) subtract(shipment.group, s.bays.find(bay => bay.sequence === shipment.sequence)?.filled ?? shipment.required);
    for (const [sequence, n] of Object.entries(s.advanceCredits)) subtract(instance.#schedule[Number(sequence) - 1].group, n);
    ensure([...balance.values()].every(n => n === 0), 'conservation');
    ensure((s.phase === 'done') === (s.cursor === instance.#schedule.length && s.bays.every(bay => bay.group === -1)), 'completion');
    ensure(typeof s.warningShown === 'boolean' && within(s.promptRemaining, 0, ROUND_LIMITS.idlePrompts) && Number.isFinite(s.quietSeconds) && s.quietSeconds >= 0 && (s.promptToken === null || s.board.includes(s.promptToken)), 'prompt');
    const trayIds = new Set(s.tray.filter(cell => cell.tokenId !== null).map(cell => cell.tokenId));
    const uniqueSubset = (array, pool) => Array.isArray(array) && new Set(array).size === array.length && array.every(id => pool.has(id));
    ensure(uniqueSubset(s.reversals, trayIds) && uniqueSubset(s.arrival, trayIds) && s.arrival.length === trayIds.size, 'tray history');
    ensure(uniqueSubset(s.scanTokens, new Set(s.board)) && s.scanTokens.length <= ROUND_LIMITS.scanCapacity && within(s.scanRemaining, 0, ROUND_LIMITS.scanCapacity), 'scan');
    if (s.scanCredits !== undefined) ensure(within(s.scanCredits, 0, 5) && s.scanTokens.length <= 1, 'scan balance');
    else {
      ensure(s.scanRemaining >= s.scanTokens.length, 'scan allocation');
      if (s.scanTracked || s.scanRemaining > 0) s.scanCredits = s.scanRemaining;
      s.scanTokens = [];
    }
    s.scanRemaining = 0;
    s.scanTracked = false;
    instance.#model = s;
    if (instance.#options.promptPolicy === 'reachable' && s.promptToken !== null) s.promptToken = instance.#choosePrompt();
    instance.#signals = [];
    return instance;
  }
}
