const POPULATION = 10000,
  INTERVAL = 600000,
  DAY_LENGTH = 86400000;
export function mixBits(seed, actor, day, salt) {
  const factors = [seed, Math.imul(actor + 1, 2654435761), Math.imul(day, 2246822507), Math.imul(salt + 1, 3266489909)];
  let value = factors.reduce((a, b) => a ^ b, 0) >>> 0;
  value = Math.imul(value ^ (value >>> 16), 2146121005);
  value = Math.imul(value ^ (value >>> 15), 2221713035);
  return (value ^ (value >>> 16)) >>> 0;
}
const fraction = (...args) => (mixBits(...args) + 0.5) / 4294967296;
const gaussian = (seed, id, day, salt) => Math.cos(2 * Math.PI * fraction(seed, id, day, salt + 1)) * Math.sqrt(-2 * Math.log(fraction(seed, id, day, salt)));
export const rivalOffset = (seed, id) => [-8, -5, 0, 1, 9][mixBits(seed, id, 0, 1) % 5];

export class RivalField {
  #parameters;
  #timetables = new Map();
  constructor(parameters) {
    this.#parameters = parameters;
  }
  profile(seed, id) {
    const sample = ((id * 37 + seed % POPULATION) % POPULATION + fraction(seed, id, 0, 201)) / POPULATION;
    let sum = 0;
    for (let i = 0; i < this.#parameters.components.length; i++) {
      const [share, mean, deviation] = this.#parameters.components[i];
      sum += share;
      if (sample < sum || i === this.#parameters.components.length - 1) return {
        component: i,
        share,
        mean,
        deviation
      };
    }
  }
  dailyBudget(seed, id, day) {
    const component = this.profile(seed, id);
    return Math.max(0, Math.min(this.#parameters.dailyLimit, Math.round(component.mean + component.deviation * gaussian(seed, id, day, 211))));
  }
  timetable(seed, id, day, budget = this.dailyBudget(seed, id, day)) {
    const p = this.#parameters,
      code = `${seed}/${id}/${day}/${budget}`;
    if (this.#timetables.has(code)) return this.#timetables.get(code).slice();
    if (!Number.isInteger(budget) || budget < 0 || budget > Math.min((p.lastTick - p.firstTick + 1) * p.tickLimit, p.dailyLimit)) throw new RangeError('Invalid daily budget');
    const output = new Uint8Array(p.ticks);
    if (budget > 0) {
      const sessions = budget <= 9 ? 1 : budget <= 24 ? 2 : 3,
        window = mixBits(seed, id, day, 220) % 3;
      const centers = Array.from({
        length: sessions
      }, (_, i) => [60, 90, 120][(window + i) % 3] + mixBits(seed, id, day, 221 + i) % 9 - 4);
      const weights = Float64Array.from({
        length: p.ticks
      }, (_, tick) => {
        if (tick < p.firstTick || tick > p.lastTick) return 0;
        let envelope = p.idle;
        for (const center of centers) envelope += Math.exp(-0.5 * ((tick - center) / p.width) ** 2);
        return envelope * -Math.log(fraction(seed, id, day, 300 + tick));
      });
      let total = weights.reduce((sum, value) => sum + value, 0);
      for (let unit = 0; unit < budget; unit++) {
        if (total <= 0) total = weights.reduce((sum, value) => sum + value, 0);
        let draw = fraction(seed, id, day, 500 + unit) * total,
          selected = p.lastTick;
        for (let tick = p.firstTick; tick <= p.lastTick; tick++) {
          if (!weights[tick]) continue;
          selected = tick;
          draw -= weights[tick];
          if (draw < 0) break;
        }
        output[selected]++;
        if (output[selected] === p.tickLimit) {
          total -= weights[selected];
          weights[selected] = 0;
        }
      }
    }
    if (this.#timetables.size >= 30000) this.#timetables.delete(this.#timetables.keys().next().value);
    this.#timetables.set(code, output);
    return output.slice();
  }
  initialRating(seed, id) {
    const target = ((id * 53 + seed % POPULATION) % POPULATION + fraction(seed, id, 0, 701)) / POPULATION * this.#parameters.samples;
    let cumulative = 0;
    for (const [rating, quantity] of this.#parameters.initial) {
      cumulative += quantity;
      if (target < cumulative) return rating;
    }
    return this.#parameters.maximum;
  }
  #quota(total) {
    const sum = this.#parameters.locales.reduce((n, [, weight]) => n + weight, 0);
    const rows = this.#parameters.locales.map(([, weight], i) => ({
      i,
      n: Math.max(1, Math.floor(total * weight / sum)),
      tail: total * weight / sum % 1
    }));
    const remaining = total - rows.reduce((n, row) => n + row.n, 0);
    if (remaining < 0) throw new RangeError('Population too small');
    const sequence = [...rows].sort((a, b) => b.tail - a.tail);
    for (let i = 0; i < remaining; i++) sequence[i % sequence.length].n++;
    return rows.map(row => row.n);
  }
  #identities(ratings) {
    const ordered = ratings.map((rating, id) => ({
      rating,
      id
    })).sort((a, b) => b.rating - a.rating || a.id - b.id);
    const quotas = this.#quota(POPULATION),
      top = this.#quota(100),
      used = quotas.map(() => 0),
      boundaries = [];
    let offset = 0;
    for (const count of quotas) {
      boundaries.push(offset);
      offset += count;
    }
    const identities = new Array(POPULATION);
    let rank = 0;
    const assign = language => {
      const identity = (boundaries[language] + used[language]++) * 2973 % POPULATION;
      const position = rank < 100 ? rank : 100 + (rank - 100) * 37 % (POPULATION - 100);
      identities[ordered[position].id] = identity;
      rank++;
    };
    while (rank < 100)
      for (let i = 0; i < top.length; i++)
        if (top[i] > 0) {
          assign(i);
          top[i]--;
        }
    for (let i = 0; i < quotas.length; i++)
      while (used[i] < quotas[i]) assign(i);
    return identities;
  }
  create(at, ceiling, salt = 0) {
    const updated = Math.floor(at / INTERVAL) * INTERVAL,
      seed = mixBits(updated ^ salt, 0, 0, 99);
    const ratings = Array.from({
      length: POPULATION
    }, (_, id) => Math.min(ceiling, this.initialRating(seed, id)));
    const leader = ratings.indexOf(Math.max(...ratings));
    ratings[leader] = Math.min(ceiling, Math.round(ratings[leader] * 1.2));
    return {
      schema: 1,
      seed,
      updated,
      ratings,
      timestamps: Array(POPULATION).fill(updated),
      identities: this.#identities(ratings)
    };
  }
  progress(record, id, start, end, ceiling) {
    let rating = record.ratings[id],
      timestamp = record.timestamps[id];
    if (rating >= ceiling || end <= start) return {
      rating,
      timestamp
    };
    const offset = rivalOffset(record.seed, id) * 3600000,
      first = Math.floor((start + offset) / INTERVAL) + 1,
      last = Math.floor((end + offset) / INTERVAL);
    let cachedDay, grid;
    for (let tick = first; tick <= last && rating < ceiling; tick++) {
      const day = Math.floor(tick / 144);
      if (day !== cachedDay) {
        grid = this.timetable(record.seed, id, day);
        cachedDay = day;
      }
      const delta = grid[tick - day * 144];
      if (delta) {
        const next = Math.min(ceiling, rating + delta);
        if (next > rating) {
          rating = next;
          timestamp = tick * INTERVAL - offset;
        }
      }
    }
    return {
      rating,
      timestamp
    };
  }
  advance(record, at, ceiling) {
    const end = Math.max(record.updated, Math.floor(at / INTERVAL) * INTERVAL),
      start = Math.max(record.updated, end - 7 * DAY_LENGTH);
    if (end === record.updated) return record;
    const progress = record.ratings.map((_, id) => this.progress(record, id, start, end, ceiling));
    return {
      ...record,
      updated: end,
      ratings: progress.map(p => p.rating),
      timestamps: progress.map(p => p.timestamp)
    };
  }
  standings(record, player) {
    const rows = record.ratings.map((rating, id) => ({
      id: record.identities[id],
      rating,
      at: record.timestamps[id],
      self: false
    }));
    if (player) rows.push({
      ...player,
      self: true
    });
    return rows.sort((a, b) => b.rating - a.rating || a.at - b.at || Number(b.self) - Number(a.self) || a.id - b.id).map((row, i) => ({
      ...row,
      rank: i + 1
    }));
  }
}
