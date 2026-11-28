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

test('AUD-05: every win returns the entry energy, as the settings text promises', async () => {
  const journal = new PlayerJournal({ clock: clockAt(0) });
  const rating = { fast: 60, medium: 100 };
  await journal.openRound(1, 'first', 'bonus1');
  await journal.completeRound(1, 30, 18, rating);
  assert.equal(journal.powerStatus().amount, 5);
  await journal.openRound(1, 'replay', 'bonus1');
  assert.equal(journal.powerStatus().amount, 4);
  const replay = await journal.completeRound(1, 30, 18, rating);
  assert.equal(replay.energy, 1);
  assert.equal(journal.powerStatus().amount, 5);
});

test('AUD-05: a loss still costs the entry energy', async () => {
  const journal = new PlayerJournal({ clock: clockAt(0) });
  await journal.openRound(1, 'lose', 'bonus1');
  await journal.checkpointRound('lose', { model: { phase: 'lost' } });
  await journal.closeLostRound('lose');
  assert.equal(journal.powerStatus().amount, 4);
});

test('AUD-05: a replay can never earn energy, even under a two-point bonus policy', async () => {
  const journal = new PlayerJournal({ clock: clockAt(0) });
  const rating = { fast: 60, medium: 100 };
  await journal.openRound(1, 'first', 'bonus2');
  const first = await journal.completeRound(1, 30, 18, rating);
  assert.equal(first.energy, 2);
  const afterFirst = journal.powerStatus().amount;
  await journal.openRound(1, 'replay', 'bonus2');
  await journal.completeRound(1, 30, 18, rating);
  assert.equal(journal.powerStatus().amount, afterFirst);
});

test('AUD-05: the classic entry policy is unchanged (no refund on a replay)', async () => {
  const journal = new PlayerJournal({ clock: clockAt(0) });
  const rating = { fast: 60, medium: 100 };
  await journal.openRound(1, 'a', 'entry');
  await journal.completeRound(1, 30, 18, rating);
  await journal.openRound(1, 'b', 'entry');
  await journal.completeRound(1, 30, 18, rating);
  assert.equal(journal.powerStatus().amount, 3);
});

// C-11 (2026-11-28): first edition ships without ads.
test('C-11 an empty tool points to the shop, never to an ad', async () => {
  const { toolDecision } = await import('../src/progress.js');
  assert.equal(toolDecision({ stage: 9, available: true, credits: 0, used: true }), 'shop');
  assert.equal(toolDecision({ stage: 9, available: true, credits: 0, used: false }), 'intro');
  assert.equal(toolDecision({ stage: 9, available: true, credits: 2, used: true }), 'credit');
});
test('C-11 shop has no remove-ads product', async () => {
  const { SHOP_PRODUCTS } = await import('../src/shop.js');
  assert.deepEqual(SHOP_PRODUCTS.map(p => p.id), ['cozy.toolbox.welcome', 'cozy.toolbox.helpers', 'cozy.space.bundle', 'cozy.energy.refill']);
  assert.ok(!SHOP_PRODUCTS.some(p => /ads?\b|noads/i.test(p.id)));
});
