import test from 'node:test';
import assert from 'node:assert/strict';
import {
  readFile
} from 'node:fs/promises';
import {
  balanceStage,
  CAMPAIGN_EDITION,
  isNeighborhood,
  toolUnlock
} from '../src/campaign.js';
import {
  Playthrough
} from '../src/playthrough.js';
import {
  PlayerJournal
} from '../src/progress.js';
import {
  SortingSession
} from '../src/session.js';
import {
  ratingFor
} from '../src/policies.js';
import {
  shopProducts,
  productPresentation
} from '../src/shop.js';
import {
  frameFor,
  viewTransform,
  worldToScreen,
  screenToWorld
} from '../src/view.js';
const load = async (number, {
  edition = 'classic'
} = {}) => {
  const p = JSON.parse(await readFile(new URL(`../data/stage-${String(number).padStart(3,'0')}.json`, import.meta.url)));
  return isNeighborhood(edition) ? balanceStage(p, number, edition) : p;
};
const targets = [18, 28, 36, 44, 52, 60, 66, 72, 64, 84, 76, 90, 98, 84, 108, 116, 104, 128, 144, 164];
test('opening campaign conserves groups and has a no-tool route through all twenty stages', async () => {
  for (let n = 1; n <= 20; n++) {
    const source = await load(n),
      before = JSON.stringify(source),
      p = balanceStage(source, n);
    assert.equal(JSON.stringify(source), before);
    assert.equal(p.stage.specimens.length, targets[n - 1]);
    const groups = new Map();
    for (const token of p.stage.specimens) groups.set(token.group, (groups.get(token.group) ?? 0) + 1);
    for (const request of p.stage.shipments) assert.equal(groups.get(request.group), request.quantity);
    const game = new SortingSession(p.stage, p.forms);
    let steps = 0;
    while (game.inspect().phase === 'live' && steps <= targets[n - 1]) {
      const s = game.inspect();
      const next = [...s.board].reverse().find(id => s.bays.some(b => b.available && b.group === p.stage.specimens[id].group) && !game.isObstructed(id));
      assert.notEqual(next, undefined, `Stage ${n}: no requested object reachable`);
      game.dispatch({
        kind: 'collect',
        tokenId: next
      });
      steps++;
    }
    assert.equal(game.inspect().phase, 'done', `Stage ${n}`);
    assert.equal(steps, targets[n - 1]);
  }
});
test('old in-flight stage keeps its edition and resume does not charge twice', async () => {
  const original = await new Playthrough({
    loadStage: load
  }).initialize();
  await original.start(1);
  await original.move({
    kind: 'collect',
    tokenId: 9
  });
  const record = original.inspect(),
    restored = await new Playthrough({
      record,
      loadStage: load,
      contentEdition: CAMPAIGN_EDITION
    }).initialize();
  assert.equal(restored.payload.stage.specimens.length, 26);
  assert.equal(restored.round.inspect().board.length, 25);
  assert.equal(await restored.start(1), 'resumed');
  assert.equal(restored.powerStatus().amount, 4);
  await restored.start(1, {
    restart: true
  });
  assert.equal(restored.payload.stage.specimens.length, 18);
  assert.equal(restored.inspect().roundEdition, CAMPAIGN_EDITION);
  const again = await new Playthrough({
    record: restored.inspect(),
    loadStage: load,
    contentEdition: CAMPAIGN_EDITION
  }).initialize();
  assert.deepEqual(again.round.save(), restored.round.save());
});
test('a campaign win returns exactly its entry energy, including after restore', async () => {
  const game = await new Playthrough({
    loadStage: load,
    contentEdition: CAMPAIGN_EDITION
  }).initialize();
  await game.start(1);
  assert.equal(game.powerStatus().amount, 4);
  while (game.inspect().player.attempt) {
    const s = game.round.inspect(),
      p = game.payload;
    const next = [...s.board].reverse().find(id => s.bays.some(b => b.available && b.group === p.stage.specimens[id].group) && !game.round.isObstructed(id));
    await game.move({
      kind: 'collect',
      tokenId: next
    });
  }
  assert.equal(game.powerStatus().amount, 5);
  assert.equal(game.inspect().result.stars, 3);
  const resumed = await new Playthrough({
    record: game.inspect(),
    loadStage: load,
    contentEdition: CAMPAIGN_EDITION
  }).initialize();
  await resumed.save();
  assert.equal(resumed.powerStatus().amount, 5);
});
test('tool unlocks are progressive and the offline shop never grants purchases', async () => {
  const player = new PlayerJournal().inspect();
  player.frontier = 7;
  const game = await new Playthrough({
    record: {
      schema: 1,
      zone: 'Asia/Shanghai',
      player,
      tries: {},
      album: null,
      result: null
    },
    loadStage: load,
    contentEdition: CAMPAIGN_EDITION
  }).initialize();
  await game.start(3);
  assert.equal((await game.use('sweep')).status, 'locked');
  assert.equal((await game.use('rub', 0)).status, 'locked');
  assert.equal(game.wallet('sweep'), 1);
  assert.equal((await game.use('scan')).status, 'applied');
  assert.deepEqual(['scan', 'return', 'sweep', 'rub'].map(k => toolUnlock(k)), [3, 4, 5, 7]);
  assert.equal(shopProducts(4).length, 0);
  assert.equal(shopProducts(5).length, 1);
  const before = game.inspect();
  for (const product of shopProducts(9)) {
    const shown = productPresentation(product);
    assert.equal(shown.purchasable, false);
    assert.equal(shown.displayPrice, null);
  }
  assert.deepEqual(game.inspect(), before);
});
test('star thresholds use the values shown by the campaign', () => {
  for (const [time, stars] of [
      [60, 3],
      [60.001, 2],
      [100, 2],
      [100.001, 1]
    ]) assert.equal(ratingFor(time, 18, undefined, {
    fast: 60,
    medium: 100
  }), stars);
  assert.throws(() => ratingFor(10, 18, undefined, {
    fast: 100,
    medium: 60
  }));
});
test('framing includes every item and pointer projection round-trips at all supported sizes', async () => {
  for (let number = 1; number <= 160; number++) {
    const p = await load(number),
      frame = frameFor(p);
    for (const [width, height] of [
        [368, 674],
        [636, 602],
        [320, 300]
      ])
      for (const magnification of [1, 1.6]) {
        const view = viewTransform(frame, width, height, magnification, [10000, -10000]);
        for (const token of p.stage.specimens) {
          const screen = worldToScreen(token.at, view, width, height),
            point = screenToWorld(screen, view, width, height);
          assert.ok(Math.abs(point[0] - token.at[0]) < 1e-9);
          assert.ok(Math.abs(point[1] - token.at[1]) < 1e-9);
        }
        if (magnification === 1) {
          const natural = viewTransform(frame, width, height);
          for (const token of p.stage.specimens) {
            const screen = worldToScreen(token.at, natural, width, height);
            assert.ok(screen[0] >= 0 && screen[0] <= width);
            assert.ok(screen[1] >= 0 && screen[1] <= height);
          }
        }
      }
  }
});

test('a previous campaign edition restores its exact request sizes during an update', async () => {
  const player = new PlayerJournal().inspect();
  player.frontier = 3;
  const first = await new Playthrough({
    record: {
      schema: 1,
      zone: 'Asia/Shanghai',
      player,
      tries: {},
      album: null,
      result: null
    },
    loadStage: load,
    contentEdition: 'neighborhood-1'
  }).initialize();
  await first.start(3);
  assert.equal(Math.max(...first.payload.stage.shipments.map(s => s.quantity)), 17);
  const after = await new Playthrough({
    record: first.inspect(),
    loadStage: load,
    contentEdition: CAMPAIGN_EDITION
  }).initialize();
  assert.deepEqual(after.round.save(), first.round.save());
  await after.start(3, {
    restart: true
  });
  assert.ok(Math.max(...after.payload.stage.shipments.map(s => s.quantity)) <= 6);
});
