// Regression tests added during Claude QA (apps/cozy-days/qa/AUDIT.md).
import test from 'node:test';
import assert from 'node:assert/strict';
import { PlayerJournal } from '../src/progress.js';

const clockAt = start => {
  let now = start;
  const clock = () => now;
  clock.add = ms => { now += ms; };
  return clock;
};

test('AUD-01: clock moved backwards keeps the next refill within one interval', async () => {
  const clock = clockAt(Date.UTC(2026, 0, 2));
  const journal = new PlayerJournal({ clock });
  for (let i = 0; i < 3; i++) await journal.openRound(1, `r${i}`, 'bonus1');
  clock.add(-24 * 3600 * 1000);
  const status = journal.powerStatus();
  assert.equal(status.amount, 2);
  assert.ok(status.refillIn > 0 && status.refillIn <= 1800, `refillIn ${status.refillIn}`);
  clock.add(1800 * 1000);
  assert.equal(journal.powerStatus().amount, 3);
});

test('AUD-01: clock moved backwards after a forward jump does not lock energy', async () => {
  const clock = clockAt(Date.UTC(2026, 0, 1));
  const journal = new PlayerJournal({ clock });
  for (let i = 0; i < 5; i++) await journal.openRound(1, `c${i}`, 'bonus1');
  clock.add(10 * 3600 * 1000);
  await journal.openRound(1, 'd', 'bonus1');
  clock.add(-10 * 3600 * 1000);
  const status = journal.powerStatus();
  assert.equal(status.amount, 4);
  assert.ok(status.refillIn <= 1800, `refillIn ${status.refillIn}`);
});
