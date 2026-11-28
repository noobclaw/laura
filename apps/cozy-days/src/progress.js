import { InvalidSaveError } from './save-recovery.js';
import {
  ACCOUNT_LIMITS,
  ratingFor
} from './policies.js';
const duplicate = value => structuredClone(value);
const purchasable = new Set(['reverse', 'return', 'scan', 'rub', 'sweep', 'bay', 'tray', 'stamina', 'previewForever', 'previewRound']);

export class PlayerJournal {
  #record;
  #clock;
  #persist;
  #pending = Promise.resolve();
  #spending = false;
  #limits;
  constructor({
    stages = 160,
    clock = Date.now,
    persist = async () => {},
    record,
    limits = {}
  } = {}) {
    this.#clock = clock;
    this.#persist = persist;
    this.#limits = {
      ...ACCOUNT_LIMITS,
      ...limits
    };
    this.stageCount = stages;
    this.#record = record ? duplicate(record) : {
      schema: 1,
      cursor: 1,
      frontier: 1,
      ratings: {},
      durations: {},
      power: this.#limits.staminaLimit,
      powerAt: clock(),
      capacity: this.#limits.staminaLimit,
      attempt: null,
      credits: {},
      gifts: {},
      receipts: [],
      acquired: {},
      used: {},
      guidance: {},
      preview: false,
      giveaways: false,
    };
    const s = this.#record;
    if (s.schema !== 1 || !Number.isInteger(s.frontier) || s.frontier < 1 || !Number.isInteger(s.cursor) || s.cursor < 1 || !Number.isFinite(s.power) || s.power < 0 || !Number.isFinite(s.powerAt) || ![5, 10, 15].includes(s.capacity)) throw new InvalidSaveError('Invalid player record');
  }
  inspect() {
    return duplicate(this.#record);
  }
  whenSettled() {
    return this.#pending;
  }
  #projectPower(record = this.#record) {
    const at = this.#clock(),
      max = record.capacity;
    let amount = record.power,
      anchor = record.powerAt;
    // A device clock moved backwards must not push the next refill hours into the future.
    // The clamped anchor is kept in memory and saved with the next successful write.
    if (anchor > at) {
      anchor = at;
      record.powerAt = at;
    }
    if (amount >= max) anchor = at;
    else {
      const intervals = Math.floor((at - anchor) / (this.#limits.refillSeconds * 1000));
      if (intervals > 0) {
        amount = Math.min(max, amount + intervals);
        anchor = amount >= max ? at : anchor + intervals * this.#limits.refillSeconds * 1000;
      }
    }
    return {
      amount,
      anchor,
      max,
      wait: amount >= max ? null : Math.ceil(this.#limits.refillSeconds - (at - anchor) / 1000)
    };
  }
  powerStatus() {
    const p = this.#projectPower();
    return {
      amount: p.amount,
      capacity: p.max,
      refillIn: p.wait
    };
  }
  #write(change) {
    const operation = this.#pending.then(async () => {
      const draft = duplicate(this.#record),
        result = await change(draft);
      if (JSON.stringify(draft) !== JSON.stringify(this.#record)) await this.#persist(duplicate(draft));
      this.#record = draft;
      return result;
    });
    this.#pending = operation.catch(() => {});
    return operation;
  }
  initializeCapacity(capacity, fresh = true) {
    return this.#write(s => {
      if (![5, 10, 15].includes(capacity)) throw new RangeError('Invalid initial capacity');
      if (s.capacityAssigned) return false;
      s.capacityAssigned = true;
      if (fresh) {
        s.capacity = capacity;
        s.power = capacity;
        s.powerAt = this.#clock();
      }
      return true;
    });
  }
  openRound(number, attemptId = crypto.randomUUID(), lifePolicy = 'entry') {
    return this.#write(s => {
      if (s.attempt?.pending) throw new Error('Reward recovery required');
      if (number < 1 || number > s.frontier) return 'locked';
      const power = this.#projectPower(s);
      let amount = power.amount;
      if (s.attempt?.checkpoint?.model.phase === 'lost' && s.attempt.lifePolicy === 'failure') amount -= Math.min(amount, this.#limits.entryCharge);
      if (amount < this.#limits.entryCharge) {
        s.power = amount;
        s.powerAt = power.anchor;
        if (s.attempt?.checkpoint?.model.phase === 'lost') s.attempt = null;
        return 'energy';
      }
      const cost = lifePolicy === 'failure' ? 0 : this.#limits.entryCharge;
      s.power = amount - cost;
      s.powerAt = power.anchor;
      s.cursor = number;
      s.attempt = {
        attemptId,
        number,
        lifePolicy,
        checkpoint: null,
        pending: null,
        preview: false
      };
      return 'ok';
    });
  }
  checkpointRound(attemptId, snapshot) {
    return this.#write(s => {
      if (s.attempt?.attemptId !== attemptId) return false;
      s.attempt.checkpoint = duplicate(snapshot);
      return true;
    });
  }
  closeLostRound(attemptId) {
    return this.#write(s => {
      if (s.attempt?.attemptId !== attemptId || s.attempt.checkpoint?.model.phase !== 'lost' || s.attempt.pending) return false;
      if (s.attempt.lifePolicy === 'failure') {
        const power = this.#projectPower(s);
        s.power = Math.max(0, power.amount - this.#limits.entryCharge);
        s.powerAt = power.anchor;
      }
      s.attempt = null;
      return true;
    });
  }
  completeRound(number, seconds, quantity, timing = 'scaled') {
    return this.#write(s => {
      if (s.attempt?.pending) throw new Error('Reward recovery required');
      if (!Number.isFinite(seconds) || seconds < 0 || !Number.isInteger(quantity) || quantity < 0) throw new RangeError('Invalid round result');
      const stars = ratingFor(seconds, quantity, this.#limits, timing),
        previous = s.ratings[number];
      const first = previous === undefined,
        improved = first || stars > previous;
      const duration = Math.ceil(seconds),
        record = s.durations[number] === undefined || duration < s.durations[number];
      const extra = s.attempt?.lifePolicy === 'bonus2' ? 2 : s.attempt?.lifePolicy === 'bonus1' ? 1 : 0;
      // Every win returns the entry energy (bonus policies). Anything above the entry charge,
      // and the classic victory refill, is paid only for a first clear or better stars,
      // so replaying a cleared stage can never earn energy.
      const refund = extra ? Math.min(extra, this.#limits.entryCharge) : 0;
      const reward = refund + (improved ? (extra ? Math.max(0, extra - refund) : this.#limits.victoryRefill) : 0);
      const power = reward ? this.#projectPower(s) : {
        amount: s.power,
        anchor: s.powerAt
      };
      const credited = extra ? reward : Math.min(reward, Math.max(0, s.capacity - power.amount));
      s.power = power.amount + credited;
      s.powerAt = power.anchor;
      s.ratings[number] = Math.max(previous ?? 0, stars);
      if (record) s.durations[number] = duration;
      const next = Math.min(number + 1, Math.max(this.stageCount, number));
      s.frontier = Math.max(s.frontier, next);
      s.cursor = next;
      s.attempt = null;
      if (improved) s.ratingAt = Math.max(s.ratingAt ?? 0, Math.max(0, Math.floor(this.#clock())));
      return {
        stars,
        best: s.durations[number],
        newBest: record,
        next,
        firstClear: first,
        ...(credited > 0 ? {
          energy: credited
        } : {})
      };
    });
  }
  grantReceipt(receipt, kind, context = null) {
    return this.#write(s => {
      if (!receipt || !purchasable.has(kind)) return 'invalid';
      if (s.receipts.includes(receipt)) return 'duplicate';
      s.receipts.push(receipt);
      if (['sweep', 'reverse', 'return', 'scan', 'rub'].includes(kind)) s.acquired[kind] = true;
      if (kind === 'previewForever') s.preview = true;
      else if (kind === 'previewRound') {
        if (s.attempt?.attemptId === context?.attemptId && s.attempt.previewRequest === context?.requestId) s.attempt.preview = true;
      } else s.credits[kind] = (s.credits[kind] ?? 0) + 1;
      return 'granted';
    });
  }
  grantStarterTools() {
    return this.#write(s => {
      if (s.giveaways) return false;
      s.giveaways = true;
      for (const kind of ['sweep', 'return', 'scan', 'rub']) s.gifts[kind] = 1;
      return true;
    });
  }
  requestPreview(attemptId, requestId) {
    return this.#write(s => {
      if (s.attempt?.attemptId !== attemptId) return false;
      s.attempt.previewRequest = requestId;
      return true;
    });
  }
  async spend(kind, {
    apply = () => true,
    snapshot,
    target,
    free = false
  } = {}) {
    if (this.#spending) return false;
    this.#spending = true;
    try {
      return await this.#spendOnce(kind, {
        apply,
        snapshot,
        target,
        free
      });
    } finally {
      this.#spending = false;
    }
  }
  async #spendOnce(kind, {
    apply,
    snapshot,
    target,
    free
  }) {
    const prepared = await this.#write(s => {
      const wallet = free ? s.gifts : s.credits;
      if (!(wallet[kind] > 0) || s.attempt?.pending) return false;
      if (kind === 'rub' && (target?.attemptId !== s.attempt?.attemptId || !Number.isSafeInteger(target?.tokenId) || target.tokenId < 0)) return false;
      const prior = snapshot?.();
      const powerBefore = kind === 'stamina' ? {
        power: s.power,
        powerAt: s.powerAt
      } : null;
      wallet[kind]--;
      if (kind === 'stamina') {
        const power = this.#projectPower(s);
        s.power = power.amount + Math.min(this.#limits.videoRefill, Math.max(0, s.capacity - power.amount));
        s.powerAt = power.anchor;
      }
      if (s.attempt && prior) s.attempt.pending = {
        kind,
        free,
        target: duplicate(target ?? null),
        prior: duplicate(prior),
        powerBefore
      };
      return {
        attemptId: s.attempt?.attemptId,
        kind,
        free,
        powerBefore
      };
    });
    if (!prepared) return false;
    let applied;
    try {
      applied = await apply();
    } catch (error) {
      await this.recoverSpend(false, undefined, prepared);
      throw error;
    }
    await this.recoverSpend(applied !== false, snapshot?.(), prepared);
    return applied !== false;
  }
  recoverSpend(applied, checkpoint, transaction) {
    return this.#write(s => {
      const pending = s.attempt?.pending ?? transaction;
      if (!pending) return false;
      if (applied) {
        if (s.attempt && checkpoint) s.attempt.checkpoint = duplicate(checkpoint);
      } else {
        const wallet = pending.free ? s.gifts : s.credits;
        wallet[pending.kind] = (wallet[pending.kind] ?? 0) + 1;
        if (pending.powerBefore) Object.assign(s, pending.powerBefore);
      }
      if (s.attempt) s.attempt.pending = null;
      return true;
    });
  }
  markUsed(kind) {
    return this.#write(s => {
      s.used[kind] = true;
    });
  }
  markGuidance(kind) {
    return this.#write(s => {
      s.guidance[kind] = true;
    });
  }
  grantEventPower(receipt, quantity) {
    return this.#write(s => {
      if (s.receipts.includes(receipt)) return 0;
      const power = this.#projectPower(s),
        credited = Math.min(Math.max(0, quantity | 0), Math.max(0, this.#limits.rewardStaminaLimit - power.amount));
      s.receipts.push(receipt);
      s.power = power.amount + credited;
      s.powerAt = s.power >= s.capacity ? this.#clock() : power.anchor;
      return credited;
    });
  }
}

export function toolDecision({
  stage,
  available,
  credits,
  used,
  unlockAt = 3
}) {
  if (stage < unlockAt) return 'locked';
  if (!available) return 'unavailable';
  // No ads in this edition (2026-11-28): an empty tool points to the shop.
  return credits > 0 ? 'credit' : used ? 'shop' : 'intro';
}
export function performTool(round, kind, target) {
  if (kind === 'reverse') return false;
  if (kind === 'return') {
    const before = round.inspect().tray.filter(cell => cell.tokenId !== null).length;
    return round.dispatch({
      kind: 'returnTray',
      tokenIds: target?.recent
    }) ? before - round.inspect().tray.filter(cell => cell.tokenId !== null).length : false;
  }
  if (kind === 'rub') return round.dispatch({
    kind: 'erase',
    tokenId: target?.tokenId
  }) ? 1 : false;
  if (kind === 'scan' && round.dispatch({
      kind: 'scanGrant'
    })) {
    round.dispatch({
      kind: 'scanActivate',
      view: target?.view
    });
    return 3;
  }
  return false;
}
