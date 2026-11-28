import test from 'node:test';
import assert from 'node:assert/strict';
import { Playthrough, PlayerJournal, meritCatalog } from '../src/index.js';

const shape = { extent: [10, 10], outline: [[-5,-5],[5,-5],[5,5],[-5,5]] };
function fixture(quantity = 8) {
  return {
    stage: {
      specimens: Array.from({ length: quantity }, (_, id) => ({ form: 'unit', group: Math.floor(id / 2), at: [id * 30, 0], stretch: [1, 1], heading: 0 })),
      shipments: Array.from({ length: quantity / 2 }, (_, group) => ({ group, quantity: 2 }))
    }, forms: { unit: shape }
  };
}
async function setup({ frontier = 1, quantity = 8, record, persist } = {}) {
  let now = Date.UTC(2026, 10, 27, 16), saved;
  const journal = new PlayerJournal({ clock: () => now }).inspect(); journal.frontier = frontier;
  const game = await new Playthrough({
    record: record ?? { schema: 1, zone: 'Asia/Shanghai', player: journal, tries: {}, album: null, result: null },
    clock: () => now, loadStage: async () => fixture(quantity),
    persist: async value => { await persist?.(value); saved = structuredClone(value); }
  }).initialize();
  return { game, saved: () => saved, time: delta => { now += delta; } };
}
async function finish(game) {
  for (const tokenId of [...game.round.inspect().board]) await game.move({ kind: 'collect', tokenId });
}

test('normal entry costs one energy; locked levels and resume cost nothing', async () => {
  const { game } = await setup();
  assert.equal(await game.start(2), 'locked'); assert.equal(game.powerStatus().amount, 5);
  assert.equal(await game.start(1), 'ok'); assert.equal(game.powerStatus().amount, 4);
  assert.equal(await game.start(1), 'resumed'); assert.equal(game.powerStatus().amount, 4);
  const restored = (await setup({ record: game.inspect() })).game;
  assert.equal(await restored.start(1), 'resumed'); assert.equal(restored.powerStatus().amount, 4);
});
test('simultaneous continue clicks open only one attempt', async () => {
  const { game } = await setup();
  assert.deepEqual(await Promise.all([game.start(1), game.start(1)]), ['ok', 'resumed']);
  assert.equal(game.powerStatus().amount, 4);
});
test('a clear atomically stores stars, next level, best time and achievements', async () => {
  const { game, saved } = await setup();
  await game.start(1); game.advance(20); await finish(game);
  assert.equal(saved().player.ratings[1], 3); assert.equal(saved().player.frontier, 2);
  assert.equal(saved().player.attempt, null); assert.equal(saved().result.seconds, 20);
  assert.equal(game.facts().tokens, 8); assert.equal(game.facts().shipments, 4);
  assert.equal(game.facts().firstFinish, true); assert.equal(game.powerStatus().amount, 4);
  const before = game.inspect(); await game.save(); await game.move({ kind: 'collect', tokenId: 0 });
  assert.deepEqual(game.inspect(), before);
});
test('the UI bridge keeps the exact three and five seconds per object rating thresholds', async () => {
  for (const [seconds, expected] of [[24,3],[24.01,2],[40,2],[40.01,1]]) {
    const { game } = await setup(); await game.start(1); game.advance(seconds); await finish(game);
    assert.equal(game.inspect().result.stars, expected);
  }
});
test('normal input cannot bypass the wallet with sandbox commands', async () => {
  const { game } = await setup(); await game.start(1);
  const before = game.round.save();
  await game.move({ kind: 'sweepBay' }); await game.move({ kind: 'expandTray' });
  assert.deepEqual(game.round.save(), before);
  assert.equal((await game.use('sweep')).status, 'locked');
  assert.equal((await game.use('tray')).status, 'empty');
});
test('starter tools appear at level three once and an empty balance never changes the board', async () => {
  const { game } = await setup({ frontier: 3 }); await game.start(3);
  assert.equal(game.wallet('sweep'), 1); assert.equal(game.wallet('return'), 1);
  assert.equal((await game.use('sweep')).status, 'applied'); assert.equal(game.wallet('sweep'), 0);
  const before = game.round.save(); assert.equal((await game.use('sweep')).status, 'empty');
  assert.deepEqual(game.round.save(), before);
  await game.start(3, { restart: true }); assert.equal(game.wallet('sweep'), 0);
});
test('starter finder reveals one object; a regular credit retains three activations across reload', async () => {
  const { game } = await setup({ frontier: 3 }); await game.start(3);
  assert.equal((await game.use('scan')).status, 'applied');
  assert.equal(game.round.inspect().scanCredits, 0); assert.equal(game.round.inspect().scanTokens.length, 1);
  const tokenId = game.round.inspect().scanTokens[0]; await game.move({ kind: 'collect', tokenId });
  assert.equal((await game.use('scan')).status, 'empty');
  const record = game.inspect(); record.player.credits.scan = 1;
  const paid = (await setup({ record })).game;
  assert.equal((await paid.use('scan')).status, 'applied'); assert.equal(paid.round.inspect().scanCredits, 2);
  const restored = (await setup({ record: paid.inspect() })).game;
  assert.equal((await restored.use('scan')).status, 'applied');
  assert.equal(restored.round.inspect().scanCredits, 2); assert.equal(restored.wallet('scan'), 0);
});
test('invalid erase targets and empty trays do not consume a starter tool', async () => {
  const { game } = await setup({ frontier: 3 }); await game.start(3);
  assert.equal((await game.use('rub', 1000)).status, 'unavailable'); assert.equal(game.wallet('rub'), 1);
  assert.equal((await game.use('return')).status, 'unavailable'); assert.equal(game.wallet('return'), 1);
  await game.move({ kind: 'collect', tokenId: 6 });
  assert.equal((await game.use('return')).status, 'applied'); assert.equal(game.wallet('return'), 0);
});
test('a failed durable write rolls back the board and wallet together', async () => {
  let reject = false;
  const { game } = await setup({ frontier: 3, persist: () => { if (reject) throw new Error('disk full'); } });
  await game.start(3); const before = game.inspect(); reject = true;
  await assert.rejects(game.use('sweep'), /disk full/); assert.deepEqual(game.inspect(), before);
  await assert.rejects(game.move({ kind: 'collect', tokenId: 0 }), /disk full/); assert.deepEqual(game.inspect(), before);
  reject = false; assert.equal((await game.use('sweep')).status, 'applied');
});
test('a failed final-clear write cannot lose the result or duplicate the achievement', async () => {
  let reject = false;
  const { game } = await setup({ quantity: 2, persist: () => { if (reject) throw new Error('disk full'); } });
  await game.start(1); await game.move({ kind: 'collect', tokenId: 0 }); reject = true;
  await assert.rejects(game.move({ kind: 'collect', tokenId: 1 }));
  assert.equal(game.inspect().player.frontier, 1); assert.deepEqual(game.round.inspect().board, [1]);
  reject = false; await game.move({ kind: 'collect', tokenId: 1 });
  assert.equal(game.inspect().player.frontier, 2); assert.equal(game.facts().tokens, 2);
});
test('energy exhaustion and the thirty-minute refill are enforced', async () => {
  const { game, time } = await setup();
  for (let i = 0; i < 5; i++) assert.equal(await game.start(1, { restart: true }), 'ok');
  assert.equal(await game.start(1, { restart: true }), 'energy'); assert.equal(game.powerStatus().amount, 0);
  assert.equal(await game.start(1), 'resumed');
  time(1800000); assert.equal(game.powerStatus().amount, 1);
  assert.equal(await game.start(1, { restart: true }), 'ok'); assert.equal(game.powerStatus().amount, 0);
});
test('level five awards an actual photo once and reading it survives restoration', async () => {
  const { game } = await setup({ frontier: 5 }); await game.start(5); await finish(game);
  assert.equal(game.albumStatus().count, 1); assert.equal(game.inspect().result.photo, 1);
  await game.save(); assert.equal(game.albumStatus().count, 1);
  await game.readPhoto(1); assert.equal(game.albumStatus().unread, 0);
  const restored = (await setup({ record: game.inspect() })).game;
  assert.equal(restored.albumStatus().count, 1); assert.equal(restored.albumStatus().unread, 0);
});
test('a full-tray loss can be resumed and the return tool revives without another entry charge', async () => {
  const { game } = await setup({ frontier: 3, quantity: 16 }); await game.start(3);
  for (const tokenId of [4,5,6,7,8,9]) await game.move({ kind: 'collect', tokenId });
  assert.equal(game.round.inspect().phase, 'lost');
  const restored = (await setup({ record: game.inspect(), quantity: 16 })).game;
  assert.equal(await restored.start(3), 'resumed'); assert.equal(restored.powerStatus().amount, 4);
  assert.equal((await restored.use('return')).status, 'applied'); assert.equal(restored.round.inspect().phase, 'live');
  assert.equal(restored.wallet('return'), 0); assert.equal(restored.powerStatus().amount, 4);
});
test('events stay locked through frontier eleven and the achievement catalog has all twenty-three goals', async () => {
  const { game } = await setup({ frontier: 11 });
  assert.deepEqual(await game.eventsStatus(), { locked: true }); assert.equal(await game.enterSprint(), null);
  assert.equal(meritCatalog().length, 23);
});
test('request completions feed race and league; reward claims commit once with energy', async () => {
  const { game } = await setup({ frontier: 12, quantity: 320 });
  await game.start(12); assert.ok(await game.enterSprint());
  for (let tokenId = 0; tokenId < 60; tokenId++) await game.move({ kind: 'collect', tokenId });
  let status = await game.eventsStatus(); assert.equal(status.sprint.score, 30); assert.equal(status.sprint.final, true);
  assert.equal(status.season.weeklyScore, 30); assert.equal(game.facts().shipments, 30);
  assert.deepEqual(await game.claimEvent('sprint'), { power: 3, added: 3 });
  assert.equal(await game.claimEvent('sprint'), null); assert.equal(game.powerStatus().amount, 7);
  for (let tokenId = 60; tokenId < 300; tokenId++) await game.move({ kind: 'collect', tokenId });
  status = await game.eventsStatus(); assert.equal(status.season.weeklyScore, 150);
  assert.deepEqual(await game.claimEvent('checkpoint', 0), { power: 2, added: 2 });
  assert.equal(await game.claimEvent('checkpoint', 0), null); assert.equal(game.powerStatus().amount, 9);
});
