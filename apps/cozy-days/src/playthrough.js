import {
  isNeighborhood,
  toolUnlock
} from './campaign.js';
import {
  SortingSession
} from './session.js?v=0.2.0';
import {
  PlayerJournal,
  performTool
} from './progress.js';
import {
  MeritBook,
  collectionView,
  advanceCollection,
  nextCollectionPhoto
} from './collections.js?v=0.2.0';
import {
  FestivalBook
} from './festivals.js';
import {
  readStage
} from './catalog.js';

const copy = value => structuredClone(value);
const pickTools = new Set(['sweep', 'return', 'scan', 'rub', 'bay', 'tray']);

// One durable document is committed before an action becomes visible to the player.
// Account, board, achievements and event rewards therefore advance together.
export class Playthrough {
  #clock;
  #persist;
  #loader;
  #cache = new Map();
  #context;
  #queue = Promise.resolve();
  #busy = 0;
  #initial;
  #edition;
  constructor({
    record,
    clock = Date.now,
    persist = async () => {},
    loadStage = readStage,
    zone = 'Asia/Shanghai',
    contentEdition = 'classic'
  } = {}) {
    if (record && record.schema !== 1) throw new TypeError('Unsupported playthrough');
    this.#edition = contentEdition;
    this.#initial = copy(record ?? {
      schema: 1,
      zone,
      tries: {},
      album: null,
      result: null
    });
    this.#clock = clock;
    this.#persist = persist;
    this.#loader = loadStage;
  }
  async initialize() {
    if (!this.#context) this.#context = await this.#hydrate(this.#initial);
    return this;
  }
  get busy() {
    return this.#busy > 0;
  }
  get round() {
    return this.#context?.round ?? null;
  }
  get payload() {
    return this.#context?.payload ?? null;
  }
  get number() {
    return this.#context?.journal.inspect().attempt?.number ?? this.#context?.data.result?.number ?? null;
  }
  async #content(number, edition = 'classic') {
    const key = `${edition}:${number}`;
    if (!this.#cache.has(key)) this.#cache.set(key, await this.#loader(number, {
      edition
    }));
    return this.#cache.get(key);
  }
  #observe(context, signal) {
    const attempt = context.journal.inspect().attempt;
    if (!attempt || !context.round) return;
    context.merits.observe(attempt.attemptId, signal, context.round.inspect());
    if (signal.kind === 'bayCompleted') context.events.addShipment(context.journal.inspect().frontier);
  }
  async #hydrate(data) {
    const context = {
      data: copy(data),
      round: null,
      payload: null
    };
    context.journal = new PlayerJournal({
      record: data.player,
      clock: this.#clock
    });
    context.merits = new MeritBook({
      record: data.merits,
      zone: data.zone
    });
    context.events = new FestivalBook({
      record: data.events,
      clock: this.#clock,
      zone: data.zone,
      award: (receipt, quantity) => context.journal.grantEventPower(receipt, quantity)
    });
    const attempt = context.journal.inspect().attempt;
    if (attempt) {
      context.payload = await this.#content(attempt.number, data.roundEdition ?? 'classic');
      const {
        stage,
        forms
      } = context.payload;
      const options = {
        onSignal: signal => this.#observe(context, signal)
      };
      context.round = attempt.checkpoint ?
        SortingSession.resume(stage, forms, attempt.checkpoint, options) :
        new SortingSession(stage, forms, options);
      if (attempt.pending) {
        // A previously persisted debit has not been published by this coordinator.
        context.round = SortingSession.resume(stage, forms, attempt.pending.prior, options);
        await context.journal.recoverSpend(false, context.round.save());
      }
    }
    return context;
  }
  #snapshot(context = this.#context) {
    const player = context.journal.inspect();
    if (player.attempt && context.round) player.attempt.checkpoint = context.round.save();
    return {
      ...copy(context.data),
      player,
      merits: context.merits.inspect(),
      events: context.events.inspect()
    };
  }
  inspect() {
    return this.#snapshot();
  }
  powerStatus() {
    return this.#context.journal.powerStatus();
  }
  facts() {
    return this.#context.merits.facts();
  }
  albumStatus() {
    return collectionView(this.#context.data.album);
  }
  advance(seconds) {
    if (this.busy || !this.round) return [];
    this.round.dispatch({
      kind: 'advance',
      seconds
    });
    return this.round.takeSignals();
  }
  #change(operation) {
    this.#busy++;
    const pending = this.#queue.then(async () => {
      const context = await this.#hydrate(this.#snapshot());
      const value = await operation(context);
      if (context.round?.inspect().phase === 'done' && context.journal.inspect().attempt) await this.#finish(context);
      await context.events.settled();
      const snapshot = this.#snapshot(context);
      await this.#persist(copy(snapshot));
      this.#context = context;
      return value;
    }).finally(() => {
      this.#busy--;
    });
    this.#queue = pending.catch(() => {});
    return pending;
  }
  async #finish(context) {
    const before = context.journal.inspect(),
      {
        attemptId,
        number
      } = before.attempt;
    const state = context.round.inspect();
    const result = await context.journal.completeRound(number, state.seconds, context.payload.stage.specimens.length, context.payload.stage.rating ?? 'scaled');
    context.merits.award(attemptId, result.stars, this.#clock());
    const photoContext = {
      stage: number,
      first: result.firstClear,
      attemptId,
      at: this.#clock()
    };
    const photo = nextCollectionPhoto(context.data.album, photoContext);
    context.data.album = advanceCollection(context.data.album, {
      ...photoContext,
      confirmed: photo
    });
    context.data.result = {
      ...result,
      number,
      seconds: state.seconds,
      photo,
      attemptId
    };
  }
  save() {
    return this.#change(() => true);
  }
  start(number, {
    restart = false
  } = {}) {
    return this.#change(async context => {
      if (!Number.isInteger(number) || number < 1 || number > 160) return 'locked';
      const previous = context.journal.inspect().attempt;
      if (!restart && previous?.number === number) return 'resumed';
      const payload = await this.#content(number, this.#edition);
      const attemptId = crypto.randomUUID();
      const response = await context.journal.openRound(number, attemptId, isNeighborhood(this.#edition) ? 'bonus1' : 'entry');
      if (response !== 'ok') return response;
      context.payload = payload;
      context.data.roundEdition = this.#edition;
      context.data.result = null;
      context.data.tries[number] = (context.data.tries[number] ?? 0) + 1;
      context.merits.begin({
        attemptId,
        stage: number,
        attempt: context.data.tries[number],
        known: true
      });
      context.round = new SortingSession(payload.stage, payload.forms, {
        onSignal: signal => this.#observe(context, signal)
      });
      if (number >= 3) await context.journal.grantStarterTools();
      return 'ok';
    });
  }
  move(action) {
    return this.#change(context => {
      if (!context.round || !context.journal.inspect().attempt || !['collect', 'pointer'].includes(action.kind)) return [];
      context.round.dispatch(action);
      context.merits.capture(context.journal.inspect().attempt.attemptId, context.round.inspect());
      return context.round.takeSignals();
    });
  }
  wallet(kind) {
    const player = this.#context.journal.inspect();
    return (player.credits[kind] ?? 0) + (player.gifts[kind] ?? 0);
  }
  use(kind, tokenId) {
    return this.#change(async context => {
      const player = context.journal.inspect(),
        round = context.round;
      if (!round || !player.attempt || !pickTools.has(kind)) return {
        status: 'unavailable'
      };
      if (!['bay', 'tray'].includes(kind) && player.attempt.number < toolUnlock(kind, context.data.roundEdition ?? 'classic')) return {
        status: 'locked'
      };
      const state = round.inspect();
      if (kind === 'scan' && ((state.scanCredits ?? 0) > 0 || state.scanTokens.length)) {
        const activation = round.dispatch({
          kind: 'scanActivate'
        });
        return {
          status: ['activated', 'refocus'].includes(activation) ? 'applied' : 'unavailable',
          signals: round.takeSignals()
        };
      }
      if (this.#available(context, kind, tokenId) === false) return {
        status: 'unavailable'
      };
      const free = (player.gifts[kind] ?? 0) > 0;
      if (!free && !(player.credits[kind] > 0)) return {
        status: 'empty'
      };
      const applied = await context.journal.spend(kind, {
        free,
        snapshot: () => round.save(),
        target: {
          attemptId: player.attempt.attemptId,
          tokenId
        },
        apply: () => {
          if (kind === 'sweep') return round.dispatch({
            kind: 'sweepBay'
          });
          if (kind === 'bay') return round.dispatch({
            kind: 'expandBay'
          });
          if (kind === 'tray') return round.dispatch({
            kind: 'expandTray'
          });
          if (kind === 'scan') {
            if (!round.dispatch({
                kind: 'scanGrant',
                quantity: free ? 1 : 3
              })) return false;
            return round.dispatch({
              kind: 'scanActivate'
            }) === 'activated';
          }
          return performTool(round, kind, {
            tokenId
          });
        }
      });
      if (applied) await context.journal.markUsed(kind);
      return {
        status: applied ? 'applied' : 'unavailable',
        signals: round.takeSignals()
      };
    });
  }
  #available(context, kind, tokenId) {
    const state = context.round.inspect();
    if (kind === 'return') return ['live', 'lost'].includes(state.phase) && state.tray.some(cell => cell.tokenId !== null);
    if (kind === 'tray') return state.phase !== 'done' && state.tray.some(cell => !cell.available);
    if (state.phase !== 'live') return false;
    if (kind === 'bay') return state.bays.some(bay => !bay.available);
    if (kind === 'sweep') return context.round.preferredBay() >= 0;
    if (kind === 'scan') return context.round.scanChoices().length > 0;
    if (kind === 'rub') return Number.isInteger(tokenId) && state.board.includes(tokenId);
    return false;
  }
  readPhoto(serial) {
    return this.#change(context => {
      const page = context.data.album?.pages?.find(page => page.serial === serial);
      if (page) page.read = true;
      return Boolean(page);
    });
  }
  eventsStatus() {
    // Status calls can roll the calendar; persist those transitions in the same transaction.
    return this.#change(context => {
      const frontier = context.journal.inspect().frontier;
      if (frontier < 12) return {
        locked: true
      };
      return {
        locked: false,
        sprint: context.events.sprintStatus(),
        season: context.events.seasonStatus(),
        starts: context.events.startsRemaining(),
        canEnter: context.events.canEnterSprint(frontier),
        pending: context.events.pendingSeason()
      };
    });
  }
  enterSprint() {
    return this.#change(context => context.events.enterSprint(context.journal.inspect().frontier));
  }
  claimEvent(kind, target) {
    return this.#change(context => {
      if (context.journal.inspect().frontier < 12) return null;
      if (kind === 'sprint') return context.events.claimSprint();
      if (kind === 'checkpoint') return context.events.claimCheckpoint(target);
      if (kind === 'season') return context.events.claimSeason(target);
      return null;
    });
  }
}
