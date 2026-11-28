import {
  LocalCalendar
} from './calendar.js';
const HOUR_LENGTH = 3600000,
  DAY_LENGTH = 86400000;
const clone = value => structuredClone(value);
export const FESTIVAL_LIMITS = Object.freeze({
  entryStage: 12,
  sprintTarget: 30,
  sprintHours: 24,
  dailyStarts: 3,
  seasonSize: 30,
  promotion: 10,
  demotion: 5,
  checkpoints: [150, 500, 1000],
  checkpointPower: [2, 3, 5],
  podiumPower: [3, 2, 1],
  seasonPower: 5,
  openingScore: 410,
  typicalRoom: 37,
  tiers: [1, 1.35, 1.8, 2.4, 3.1]
});

function checksum(text) {
  let result = 2166136261;
  for (const character of text) result = Math.imul(result ^ character.charCodeAt(0), 16777619);
  return result >>> 0;
}

function stream(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 1831565813) >>> 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function trajectory(seed, divisions) {
  const random = stream(seed),
    weights = Array.from({
      length: divisions
    }, () => random() < 0.35 ? 0.15 : 0.4 + random() * 1.6),
    sum = weights.reduce((a, b) => a + b, 0);
  let position = 0;
  return weights.map(weight => position += weight / sum);
}

function interpolate(trajectory, fraction) {
  if (fraction <= 0) return 0;
  if (fraction >= 1) return 1;
  const position = fraction * trajectory.length,
    index = Math.floor(position),
    before = index ? trajectory[index - 1] : 0;
  return before + (trajectory[index] - before) * (position - index);
}

export class FestivalBook {
  #data;
  #clock;
  #calendar;
  #persist;
  #award;
  #queue = Promise.resolve();
  constructor({
    record,
    clock = Date.now,
    zone,
    persist = async () => {},
    award = async (_, quantity) => quantity,
    openingScore = 410
  } = {}) {
    this.#data = clone(record ?? {
      schema: 1,
      sprint: null,
      statistics: {
        starts: 0,
        wins: 0,
        podiums: 0,
        pace: 1
      },
      season: null,
      archives: []
    });
    this.#clock = clock;
    this.#data.zone ??= zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
    this.#calendar = new LocalCalendar(this.#data.zone);
    this.#persist = persist;
    this.#award = award;
    this.openingScore = openingScore;
  }
  inspect() {
    return clone(this.#data);
  }
  #enqueue(operation) {
    const pending = this.#queue.then(operation);
    this.#queue = pending.catch(() => {});
    return pending;
  }
  #save() {
    return this.#enqueue(() => this.#persist(this.inspect()));
  }
  settled() {
    return this.#queue;
  }
  #today(at) {
    const day = this.#data.day;
    return day ? (at < day.reset ? day.number : Math.max(this.#calendar.dayNumber(at), day.number + 1)) : this.#calendar.dayNumber(at);
  }
  startsRemaining(at = this.#clock()) {
    const today = this.#today(at);
    return 3 - (this.#data.day?.number === today ? this.#data.day.count : 0);
  }
  nextReset(at = this.#clock()) {
    const today = this.#today(at);
    return this.#data.day?.number === today ? this.#data.day.reset : this.#calendar.midnight(today + 1);
  }
  canEnterSprint(frontier, at = this.#clock()) {
    const current = this.#data.sprint;
    return frontier >= 12 && (!current || (current.claimed && at > current.begin)) && this.startsRemaining(at) > 0;
  }
  enterSprint(frontier) {
    const at = this.#clock();
    if (!this.canEnterSprint(frontier, at)) return null;
    const today = this.#today(at),
      oldDay = this.#data.day;
    this.#data.day = oldDay?.number === today ? {
      ...oldDay,
      count: oldDay.count + 1
    } : {
      number: today,
      count: 1,
      reset: this.#calendar.midnight(today + 1)
    };
    const seed = checksum('race:' + at),
      random = stream(seed);
    const rivals = [
      [0.25, 0.4],
      [0.35, 0.6],
      [0.55, 1.1],
      [1, 2.2]
    ].map(([low, high], i) => {
      const duration = (low + random() * (high - low)) * this.#data.statistics.pace;
      return {
        identity: Math.floor(random() * 10000),
        seed: checksum(seed + ':' + i),
        finish: Math.round(at + duration * HOUR_LENGTH)
      };
    });
    this.#data.sprint = {
      key: 'sprint-' + at,
      begin: at,
      end: at + 24 * HOUR_LENGTH,
      score: 0,
      finish: null,
      position: null,
      claimed: false,
      rivals,
      boosts: {},
      chasedAt: at,
      lastScoreAt: at,
      passed: null,
      seen: null
    };
    this.#save();
    return this.sprintStatus(at);
  }
  #rivalScore(sprint, rival, at, index, boost = true) {
    const fraction = (Math.min(at, sprint.end) - sprint.begin) / (rival.finish - sprint.begin);
    const base = Math.min(30, Math.floor(30 * interpolate(trajectory(rival.seed, 24), fraction)));
    return base >= 30 ? base : Math.max(base, Math.min(base + (boost ? (sprint.boosts[index] ?? 0) : 0), 29));
  }
  #pursue(sprint, at) {
    if (sprint.position !== null) return false;
    let changed = false,
      iterations = 0;
    while (sprint.chasedAt + 120000 <= Math.min(at, sprint.end) && iterations++ < 800) {
      sprint.chasedAt += 120000;
      changed = true;
      let candidate = -1,
        score = -1;
      sprint.rivals.forEach((rival, i) => {
        const value = this.#rivalScore(sprint, rival, sprint.chasedAt, i);
        if (value < sprint.score && value < 30 && value > score) {
          candidate = i;
          score = value;
        }
      });
      if (candidate < 0) continue;
      if (sprint.score - score > 2) sprint.boosts[candidate] = (sprint.boosts[candidate] ?? 0) + 1;
      else if (sprint.chasedAt - sprint.lastScoreAt >= 900000 && (sprint.passed?.at ?? 0) < sprint.lastScoreAt && sprint.score + 1 < 30) {
        const base = this.#rivalScore(sprint, sprint.rivals[candidate], sprint.chasedAt, candidate, false);
        sprint.boosts[candidate] = Math.max(sprint.boosts[candidate] ?? 0, sprint.score + 1 - base);
        sprint.passed = {
          identity: sprint.rivals[candidate].identity,
          at: sprint.chasedAt
        };
      }
    }
    return changed;
  }
  #sprintTable(sprint, at) {
    const rows = sprint.rivals.map((rival, i) => {
      const score = this.#rivalScore(sprint, rival, at, i);
      return {
        identity: rival.identity,
        score,
        finish: score >= 30 ? Math.min(rival.finish, sprint.end) : null,
        self: false
      };
    });
    rows.push({
      identity: 'self',
      score: sprint.score,
      finish: sprint.finish,
      self: true
    });
    rows.sort((a, b) => (a.finish !== null) !== (b.finish !== null) ? a.finish !== null ? -1 : 1 : a.finish !== null ? a.finish - b.finish : b.score - a.score || Number(b.self) - Number(a.self));
    return rows.map((row, i) => ({
      ...row,
      position: i + 1
    }));
  }
  #finishSprint(sprint, at) {
    if (sprint.position !== null) return;
    const table = this.#sprintTable(sprint, at),
      ahead = table.filter(row => !row.self && row.finish !== null).length;
    if (at < sprint.end && sprint.finish === null && ahead < 3) return;
    const position = table.find(row => row.self).position;
    sprint.position = sprint.finish !== null ? position : Math.max(4, position);
    const stats = this.#data.statistics;
    stats.starts++;
    if (sprint.position === 1) stats.wins++;
    if (sprint.position <= 3) stats.podiums++;
    stats.pace = Math.min(1.4, Math.max(0.7, stats.pace * (sprint.position === 1 ? 0.9 : sprint.position <= 3 ? 1 : 1.1)));
  }
  sprintStatus(at = this.#clock()) {
    const sprint = this.#data.sprint;
    if (!sprint) return null;
    const changed = this.#pursue(sprint, at),
      pending = sprint.position === null;
    this.#finishSprint(sprint, at);
    if (changed || (pending && sprint.position !== null)) this.#save();
    const table = this.#sprintTable(sprint, at);
    return {
      key: sprint.key,
      begin: sprint.begin,
      end: sprint.end,
      target: 30,
      table,
      position: sprint.position ?? table.find(row => row.self).position,
      final: sprint.position !== null,
      claimed: sprint.claimed,
      score: sprint.score,
      passed: clone(sprint.passed),
      seen: clone(sprint.seen),
      startsLeft: this.startsRemaining(at),
      reset: this.nextReset(at),
      reward: sprint.position !== null && sprint.position <= 3 ? [3, 2, 1][sprint.position - 1] : null
    };
  }
  acknowledgeSprint(view) {
    const sprint = this.#data.sprint;
    if (!view || sprint?.key !== view.key) return;
    sprint.seen = {
      at: this.#clock(),
      scores: Object.fromEntries(view.table.map(row => [row.identity, row.score])),
      positions: Object.fromEntries(view.table.map(row => [row.identity, row.position]))
    };
    this.#save();
  }
  claimSprint() {
    const view = this.sprintStatus();
    if (!view?.final || view.claimed) return Promise.resolve(null);
    return this.#enqueue(async () => {
      if (this.#data.sprint?.key !== view.key || this.#data.sprint.claimed) return null;
      const amount = view.reward ?? 0,
        added = await this.#award(view.key, amount);
      this.#data.sprint.claimed = true;
      await this.#persist(this.inspect());
      return {
        power: amount,
        added
      };
    });
  }
  #newSeason(week, tier, at, {
    begin = this.#calendar.midnight(week),
    end = this.#calendar.midnight(week + 7),
    openAt = begin
  } = {}) {
    this.#data.seasonSeed ??= checksum(String(this.#clock()));
    const seed = checksum('league:' + begin + ':' + tier + ':' + this.#data.seasonSeed),
      random = stream(seed);
    const first = !this.#data.season && !this.#data.archives.length,
      leading = first ? 0.14 : Math.min(0.95, 0.8 + 0.03 * tier);
    const rivals = Array.from({
      length: 29
    }, (_, i) => {
      const order = 1 - i / 29,
        share = Math.max(0.06, Math.min(1, Math.pow(order, 1 - 0.12 * tier) + (random() - 0.5) * 0.06));
      const initial = first ? Math.max(0, this.openingScore + Math.round(37 * (3.4 - 4.4 * random()))) : 0;
      return {
        identity: Math.floor(random() * 10000),
        seed: checksum(seed + ':' + i),
        daily: Math.round(148 * leading * share),
        initial
      };
    });
    return {
      week,
      begin,
      end,
      tier,
      from: first ? at : Math.max(begin, openAt),
      base: first ? this.openingScore : 0,
      score: 0,
      rivals,
      claimed: []
    };
  }
  #seasonTable(season, at) {
    const span = Math.max(1, season.end - season.from),
      fraction = Math.max(0, Math.min(1, (at - season.from) / span));
    const rows = season.rivals.map(rival => ({
      identity: rival.identity,
      self: false,
      score: rival.initial + Math.floor(rival.daily * (span / DAY_LENGTH) * (0.75 * fraction + 0.25 * interpolate(trajectory(rival.seed, 42), fraction)))
    }));
    rows.push({
      identity: 'self',
      self: true,
      score: season.base + season.score
    });
    rows.sort((a, b) => b.score - a.score || Number(b.self) - Number(a.self) || a.identity - b.identity);
    return rows.map((row, i) => ({
      ...row,
      position: i + 1
    }));
  }
  #rollSeason(at) {
    const current = this.#calendar.weekNumber(at),
      old = this.#data.season;
    if (old && at >= old.end) {
      const position = this.#seasonTable(old, old.end - 1).find(row => row.self).position;
      const change = old.score > 0 && position <= 10 ? 1 : position > 25 ? -1 : 0,
        tier = Math.max(0, Math.min(4, old.tier + change));
      this.#data.archives.push({
        begin: old.begin,
        tier: old.tier,
        nextTier: tier,
        position,
        score: old.base + old.score,
        power: old.score === 0 ? 0 : 5,
        seen: false
      });
      const week = Math.max(current, old.week + 7),
        begin = current < week ? old.end : this.#calendar.midnight(week);
      this.#data.season = this.#newSeason(week, tier, at, {
        begin,
        openAt: old.end
      });
      this.#save();
    }
    if (!this.#data.season) {
      this.#data.season = this.#newSeason(current, 0, at);
      this.#save();
    }
  }
  seasonStatus(at = this.#clock()) {
    this.#rollSeason(at);
    const season = this.#data.season,
      table = this.#seasonTable(season, at);
    return {
      begin: season.begin,
      end: season.end,
      tier: season.tier,
      score: season.base + season.score,
      weeklyScore: season.score,
      table,
      position: table.find(row => row.self).position,
      promote: season.tier < 4 ? 10 : 0,
      demote: season.tier > 0 ? 5 : 0,
      milestones: [150, 500, 1000].map((threshold, i) => ({
        threshold,
        power: [2, 3, 5][i],
        reached: season.score >= threshold,
        claimed: season.claimed.includes(i)
      }))
    };
  }
  addShipment(frontier) {
    if (frontier < 12) return null;
    const at = this.#clock();
    this.#rollSeason(at);
    const season = this.#data.season;
    const before = this.#seasonTable(season, at).find(row => row.self).position;
    season.score++;
    const after = this.#seasonTable(season, at).find(row => row.self).position;
    let sprintChange = null;
    const sprint = this.#data.sprint;
    if (sprint && sprint.position === null && at < sprint.end && sprint.score < 30) {
      this.#pursue(sprint, at);
      sprint.lastScoreAt = at;
      const previous = this.#sprintTable(sprint, at).find(row => row.self).position;
      sprint.score++;
      if (sprint.score >= 30) sprint.finish = at;
      const next = this.#sprintTable(sprint, at).find(row => row.self).position;
      this.#finishSprint(sprint, at);
      sprintChange = {
        score: sprint.score,
        before: previous,
        after: next,
        finished: sprint.finish !== null,
        final: sprint.position
      };
    }
    this.#save();
    return {
      sprint: sprintChange,
      season: {
        score: season.score,
        before,
        after,
        milestone: [150, 500, 1000].indexOf(season.score)
      }
    };
  }
  claimCheckpoint(index) {
    this.#rollSeason(this.#clock());
    const season = this.#data.season,
      threshold = [150, 500, 1000][index],
      begin = season.begin;
    if (!threshold || season.score < threshold || season.claimed.includes(index)) return Promise.resolve(null);
    return this.#enqueue(async () => {
      const current = this.#data.season;
      if (current.begin !== begin || current.claimed.includes(index) || current.score < threshold) return null;
      const power = [2, 3, 5][index],
        added = await this.#award(`season-${begin}-${index}`, power);
      current.claimed.push(index);
      await this.#persist(this.inspect());
      return {
        power,
        added
      };
    });
  }
  pendingSeason() {
    this.#rollSeason(this.#clock());
    return clone(this.#data.archives.find(entry => !entry.seen) ?? null);
  }
  claimSeason(begin) {
    const result = this.pendingSeason();
    if (!result || result.begin !== begin) return Promise.resolve(null);
    return this.#enqueue(async () => {
      const current = this.#data.archives.find(entry => entry.begin === begin && !entry.seen);
      if (!current) return null;
      const added = await this.#award(`season-${begin}-final`, current.power);
      current.seen = true;
      await this.#persist(this.inspect());
      return {
        power: current.power,
        added
      };
    });
  }
  notice(frontier, at = this.#clock()) {
    if (frontier < 12) return null;
    this.#rollSeason(at);
    const season = this.#data.season;
    if (!this.#data.announced) return {
      kind: 'unlock',
      key: 'unlock',
      begin: season.begin,
      tier: season.tier,
      end: season.end
    };
    if (this.#data.announced !== season.begin && this.#data.announced !== 'unlock:' + season.begin) return {
      kind: 'week',
      key: season.begin,
      begin: season.begin,
      tier: season.tier,
      end: season.end
    };
    return null;
  }
  acknowledgeNotice(notice) {
    if (notice) {
      this.#data.announced = notice.kind === 'unlock' ? 'unlock:' + notice.begin : notice.begin;
      this.#save();
    }
  }
  summary(frontier, at = this.#clock()) {
    if (frontier < 12) return {
      locked: true
    };
    const sprint = this.sprintStatus(at),
      season = this.seasonStatus(at);
    return {
      locked: false,
      sprint,
      season: {
        tier: season.tier,
        position: season.position,
        score: season.score,
        weeklyScore: season.weeklyScore
      },
      claimable: (sprint?.final && !sprint.claimed ? 1 : 0) + season.milestones.filter(m => m.reached && !m.claimed).length + this.#data.archives.filter(entry => !entry.seen).length
    };
  }
}
