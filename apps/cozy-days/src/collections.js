import {
  LocalCalendar
} from './calendar.js';
const clone = value => structuredClone(value);
export const COLLECTION_LIMITS = Object.freeze({
  firstStage: 5,
  pointsPerPhoto: 3,
  photoCount: 48,
  pageSize: 6
});
export function collectionView(raw) {
  const pages = [];
  for (let serial = 1; serial <= COLLECTION_LIMITS.photoCount; serial++) {
    const page = raw?.pages?.find(entry => entry.serial === serial && Number.isFinite(entry.timestamp));
    if (!page) break;
    pages.push({
      serial,
      timestamp: page.timestamp,
      read: page.read === true
    });
  }
  const full = pages.length === COLLECTION_LIMITS.photoCount;
  return {
    pages,
    count: pages.length,
    full,
    vouchers: Number.isInteger(raw?.vouchers) ? Math.max(0, Math.min(COLLECTION_LIMITS.photoCount - pages.length, raw.vouchers)) : 0,
    points: !full && Number.isInteger(raw?.points) && raw.points >= 0 && raw.points < 3 ? raw.points : 0,
    unread: pages.filter(page => !page.read).length,
    lastDate: typeof raw?.lastDate === 'string' ? raw.lastDate : '',
    lastAttempt: typeof raw?.lastAttempt === 'string' ? raw.lastAttempt : ''
  };
}
export function advanceCollection(raw, {
  stage,
  first,
  attemptId,
  at,
  confirmed
} = {}) {
  if (!Number.isInteger(stage) || stage < 5 || typeof attemptId !== 'string' || !attemptId || !Number.isFinite(at)) return raw;
  const view = collectionView(raw),
    day = new LocalCalendar().dateLabel(at);
  if (view.full || view.lastAttempt === attemptId || raw?.creditedAttempts?.includes(attemptId)) return raw;
  const pages = clone(view.pages);
  let points = view.points,
    vouchers = view.vouchers;
  if (!pages.length && !vouchers) vouchers++;
  else if (first) points++;
  if (day > view.lastDate) points++;
  while (points >= 3 && pages.length + vouchers < COLLECTION_LIMITS.photoCount) {
    points -= 3;
    vouchers++;
  }
  if (vouchers > 0 && confirmed === pages.length + 1) {
    pages.push({
      serial: confirmed,
      timestamp: at,
      read: false
    });
    vouchers--;
  }
  if (pages.length + vouchers === COLLECTION_LIMITS.photoCount) points = 0;
  return {
    schema: 1,
    pages,
    vouchers,
    points: pages.length === COLLECTION_LIMITS.photoCount ? 0 : points,
    lastDate: day > view.lastDate ? day : view.lastDate,
    lastAttempt: attemptId,
    creditedAttempts: [...(Array.isArray(raw?.creditedAttempts) ? raw.creditedAttempts.filter(id => typeof id === 'string').slice(-100) : []), attemptId]
  };
}
export function nextCollectionPhoto(raw, context) {
  if (!Number.isInteger(context?.stage) || context.stage < 5) return null;
  const projection = advanceCollection(raw, context);
  return projection?.vouchers > 0 ? collectionView(projection).count + 1 : null;
}

const targets = [
  ['shipping-30', 'shipments', 30],
  ['sorting-50', 'tokens', 50],
  ['first-finish', 'firstFinish'],
  ['stage-3', 'stage3'],
  ['shipping-50', 'shipments', 50],
  ['stage-10', 'stage10'],
  ['stage-30', 'stage30'],
  ['stage-100', 'stage100'],
  ['first-perfect', 'firstPerfect'],
  ['perfect-10', 'perfectStages', 10],
  ['perfect-30', 'perfectStages', 30],
  ['perfect-50', 'perfectStages', 50],
  ['improved-rating', 'improved'],
  ['shipping-100', 'shipments', 100],
  ['shipping-1000', 'shipments', 1000],
  ['sorting-1000', 'tokens', 1000],
  ['sorting-10000', 'tokens', 10000],
  ['first-unaided', 'firstUnaided'],
  ['unaided-10', 'unaidedStages', 10],
  ['first-attempt-perfect', 'firstAttemptPerfect'],
  ['narrow-escape', 'narrowEscape'],
  ['days-3', 'days', 3],
  ['days-7', 'days', 7],
];
export function meritCatalog() {
  return targets.map(([key, metric, target = 1]) => ({ key, metric, target }));
}
export class MeritBook {
  #profile;
  #calendar;
  constructor({
    record,
    zone = 'Asia/Shanghai'
  } = {}) {
    this.#profile = clone(record ?? {
      schema: 1,
      stages: {},
      attempts: {},
      flags: {}
    });
    this.#profile.zone ??= zone;
    this.#calendar = new LocalCalendar(this.#profile.zone);
  }
  inspect() {
    return clone(this.#profile);
  }
  begin({
    attemptId,
    stage,
    attempt = 1,
    known = false
  }) {
    if (!this.#profile.attempts[attemptId]) this.#profile.attempts[attemptId] = {
      stage,
      attempt,
      known,
      tokens: [],
      shipments: [],
      aided: false,
      expanded: false,
      continued: false,
      danger: false,
      invalidDanger: false,
      award: null
    };
    return attemptId;
  }
  observe(attemptId, signal, round) {
    const run = this.#profile.attempts[attemptId];
    if (!run || run.award) return;
    const append = (key, value) => {
      if (value !== null && !run[key].includes(value)) run[key].push(value);
    };
    if (['boardDelivered', 'trayDelivered'].includes(signal.kind)) append('tokens', signal.tokenId);
    if (signal.assisted) run.aided = true;
    if (signal.kind === 'bayCompleted') append('shipments', round.bays[signal.bay]?.sequence ?? null);
    if (['bayExpanded', 'tokenErased', 'selectionReversed', 'trayReturned', 'scanHighlighted', 'scanFocused'].includes(signal.kind)) run.aided = true;
    const expanded = signal.kind === 'trayExpanded',
      continued = signal.continued === true && ['trayExpanded', 'trayReturned'].includes(signal.kind);
    if (expanded || continued) {
      run.aided = true;
      run.expanded ||= expanded;
      run.continued ||= continued;
      run.invalidDanger ||= run.danger;
    }
    if (signal.kind === 'trayNearlyFull') this.capture(attemptId, round);
  }
  capture(attemptId, round, aids = 0) {
    const run = this.#profile.attempts[attemptId];
    if (!run || run.award) return;
    if (aids > 0) run.aided = true;
    const cells = round.tray.filter(cell => cell.available);
    if (round.phase === 'live' && cells.length >= 2 && cells.filter(cell => cell.tokenId === null).length === 1) run.danger = true;
  }
  award(attemptId, stars, at) {
    const run = this.#profile.attempts[attemptId];
    if (!run) return false;
    if (run.award) {
      if (run.award.stars !== stars) throw new Error('Award changed');
      return false;
    }
    if (!Number.isInteger(stars) || stars < 1 || stars > 3) throw new RangeError('Invalid rating');
    const prior = this.#profile.stages[run.stage] ?? 0;
    run.award = {
      stars,
      day: this.#calendar.dateLabel(at),
      prior
    };
    this.#profile.stages[run.stage] = Math.max(prior, stars);
    const flags = this.#profile.flags;
    flags.firstFinish = true;
    if ([3, 10, 30, 100].includes(run.stage)) flags['stage' + run.stage] = true;
    flags.improved ||= stars === 3 && [1, 2].includes(prior);
    flags.firstAttemptPerfect ||= run.stage >= 3 && run.known && run.attempt === 1 && stars === 3;
    flags.narrowEscape ||= run.danger && !run.invalidDanger;
    return true;
  }
  facts() {
    const runs = Object.values(this.#profile.attempts),
      finished = runs.filter(run => run.award),
      unaided = new Set(finished.filter(run => !run.aided).map(run => run.stage));
    const perfectStages = Math.min(50, Object.values(this.#profile.stages).filter(stars => stars === 3).length);
    return {
      ...this.#profile.flags,
      shipments: Math.min(1000, runs.reduce((sum, run) => sum + run.shipments.length, 0)),
      tokens: Math.min(10000, runs.reduce((sum, run) => sum + run.tokens.length, 0)),
      days: Math.min(7, new Set(finished.map(run => run.award.day)).size),
      unaidedStages: Math.min(10, unaided.size),
      firstUnaided: unaided.size > 0,
      perfectStages,
      firstPerfect: perfectStages > 0
    };
  }
  goals() {
    const facts = this.facts();
    return targets.flatMap(([key, metric, ceiling]) => ceiling ? facts[metric] > 0 ? [{
      key,
      steps: Math.min(ceiling, facts[metric])
    }] : [] : facts[metric] ? [{
      key
    }] : []);
  }
}
