export class LocalCalendar {
  #format;
  #offset;
  #cache = new Map();
  constructor(zone = Intl.DateTimeFormat().resolvedOptions().timeZone) {
    if (typeof zone === 'number') this.#offset = zone * 60000;
    else this.#format = new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      calendar: 'gregory',
      numberingSystem: 'latn',
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }
  #wall(at) {
    if (!this.#format) return at - this.#offset;
    const f = Object.fromEntries(this.#format.formatToParts(at).filter(p => p.type !== 'literal').map(p => [p.type, Number(p.value)]));
    return Date.UTC(f.year, f.month - 1, f.day, f.hour % 24, f.minute, f.second);
  }
  dayNumber(at) {
    return Math.floor(this.#wall(at) / 86400000);
  }
  dateLabel(at) {
    return new Date(this.dayNumber(at) * 86400000).toISOString().slice(0, 10);
  }
  midnight(day) {
    if (!this.#format) return day * 86400000 + this.#offset;
    if (this.#cache.has(day)) return this.#cache.get(day);
    const nominal = day * 86400000;
    const candidates = [-1, 0, 1].map(delta => nominal + delta * 86400000).map(at => nominal - (this.#wall(at) - at)).filter(at => this.#wall(at) === nominal);
    let boundary;
    if (candidates.length) boundary = Math.min(...candidates);
    else {
      let lo = nominal - 86400000,
        hi = nominal + 86400000;
      while (hi - lo > 1) {
        const mid = Math.floor((lo + hi) / 2);
        if (this.dayNumber(mid) < day) lo = mid;
        else hi = mid;
      }
      boundary = hi;
    }
    if (this.#cache.size >= 8) this.#cache.clear();
    this.#cache.set(day, boundary);
    return boundary;
  }
  weekNumber(at) {
    return Math.floor((this.dayNumber(at) + 3) / 7) * 7 - 3;
  }
  weekBoundary(at) {
    return this.midnight(this.weekNumber(at));
  }
}
