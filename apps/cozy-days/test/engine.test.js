import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SortingSession,
  PlayerJournal,
  Spatial,
  LocalCalendar,
  advanceCollection,
  nextCollectionPhoto
} from '../src/index.js';
const rectangle = [
  [-10, -10],
  [10, -10],
  [10, 10],
  [-10, 10]
];
const forms = {
  tile: {
    extent: [20, 20],
    outline: rectangle
  }
};
const stage = {
  specimens: [1, 1, 2, 2, 3, 3, 4, 4].map((group, id) => ({
    form: 'tile',
    group,
    at: [id * 40, 0],
    stretch: [1, 1],
    heading: 0
  })),
  shipments: [1, 2, 3, 4].map(group => ({
    group,
    quantity: 2
  }))
};
const fresh = options => new SortingSession(stage, forms, options);

test('visible touch selection never redirects a blocked direct hit to another requested object', () => {
  const placements = [
    { form: 'tile', group: 1, at: [0,0], stretch: [1,1], heading: 0 },
    { form: 'tile', group: 2, at: [15,0], stretch: [1,1], heading: 0 }
  ];
  const round = new SortingSession({ specimens: placements, shipments: [{group:1,quantity:1},{group:2,quantity:1}] }, forms);
  assert.equal(round.isObstructed(0), true);
  assert.equal(round.locate([-1,0], 12, 'visible'), 0);
  const before = round.inspect();
  round.dispatch({ kind: 'pointer', point: [-1,0], radius: 12, preference: 'visible' });
  assert.deepEqual(round.inspect().board, before.board);
  assert.deepEqual(round.inspect().bays, before.bays);
  assert.equal(round.takeSignals().at(-1).kind, 'selectionBlocked');
});

test('a stored token returns to its original stacking position', () => {
  const round = fresh();
  round.dispatch({
    kind: 'collect',
    tokenId: 6
  });
  round.dispatch({
    kind: 'collect',
    tokenId: 7
  });
  assert.deepEqual(round.latestTrayTokens(), [7, 6]);
  assert.equal(round.dispatch({
    kind: 'reverse'
  }), true);
  assert.deepEqual(round.inspect().board, [0, 1, 2, 3, 4, 5, 7]);
  assert.deepEqual(round.latestTrayTokens(), [6]);
});
test('completed requests pull waiting objects through chained requests', () => {
  const round = fresh();
  for (const id of [4, 5, 6, 7]) round.dispatch({
    kind: 'collect',
    tokenId: id
  });
  for (const id of [0, 1, 2, 3]) round.dispatch({
    kind: 'collect',
    tokenId: id
  });
  assert.equal(round.inspect().phase, 'done');
  assert.equal(round.inspect().board.length, 0);
  assert.equal(round.inspect().tray.filter(c => c.tokenId !== null).length, 0);
});
test('a future erased object is credited exactly once when its request opens', () => {
  const round = fresh();
  round.dispatch({
    kind: 'erase',
    tokenId: 4
  });
  const resumed = SortingSession.resume(stage, forms, round.save());
  resumed.dispatch({
    kind: 'sweepBay'
  });
  assert.equal(resumed.inspect().bays[0].group, 3);
  assert.equal(resumed.inspect().bays[0].filled, 1);
  resumed.dispatch({
    kind: 'sweepBay'
  });
  resumed.dispatch({
    kind: 'sweepBay'
  });
  resumed.dispatch({
    kind: 'sweepBay'
  });
  assert.equal(resumed.inspect().phase, 'done');
});
test('checkpoint corruption cannot duplicate objects or manufacture progress', () => {
  const round = fresh();
  round.dispatch({
    kind: 'collect',
    tokenId: 6
  });
  const saved = round.save();
  const mutations = [s => s.model.board.push(6), s => s.model.bays[0].filled++, s => s.model.tray[1].tokenId = 6, s => s.binding++, s => s.model.arrival.push(6), s => s.model.seconds = -1, s => s.model.scanTokens = [99]];
  for (const mutate of mutations) {
    const invalid = structuredClone(saved);
    mutate(invalid);
    assert.throws(() => SortingSession.resume(stage, forms, invalid));
  }
  assert.deepEqual(SortingSession.resume(stage, forms, saved).save(), saved);
});
test('a four-bay round reveals the fourth bay only after expanding the third', () => {
  const round = fresh({
    bays: 4
  });
  assert.equal(round.visibleBays, 3);
  assert.equal(round.dispatch({
    kind: 'expandBay',
    bay: 3
  }), false);
  assert.equal(round.dispatch({
    kind: 'expandBay',
    bay: 2
  }), true);
  assert.equal(round.visibleBays, 4);
  assert.equal(round.dispatch({
    kind: 'expandBay',
    bay: 3
  }), true);
});
test('a scan grant is consumed once and refocusing does not consume another credit', () => {
  const round = fresh();
  assert.equal(round.dispatch({
    kind: 'scanGrant'
  }), true);
  assert.equal(round.dispatch({
    kind: 'scanActivate'
  }), 'activated');
  assert.equal(round.inspect().scanCredits, 2);
  assert.equal(round.dispatch({
    kind: 'scanActivate'
  }), 'refocus');
  assert.equal(round.inspect().scanCredits, 2);
  assert.equal(round.dispatch({
    kind: 'scanGrant'
  }), false);
});
test('automatic prompts respect pause and idle threshold', () => {
  const round = fresh();
  round.dispatch({
    kind: 'pausePrompts',
    paused: true
  });
  round.dispatch({
    kind: 'advance',
    seconds: 20
  });
  assert.equal(round.inspect().promptToken, null);
  round.dispatch({
    kind: 'pausePrompts',
    paused: false
  });
  round.dispatch({
    kind: 'advance',
    seconds: 14.99
  });
  assert.equal(round.inspect().promptToken, null);
  round.dispatch({
    kind: 'advance',
    seconds: 0.01
  });
  assert.notEqual(round.inspect().promptToken, null);
  assert.equal(round.inspect().promptRemaining, 2);
});
test('transparent pixels do not create a selectable object', () => {
  const definition = {
    extent: [2, 2],
    outline: [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1]
    ],
    grid: {
      columns: 2,
      rows: 2,
      bits: 'Aw=='
    }
  };
  const contour = Spatial.composeOutline(definition, {
    at: [0, 0],
    stretch: [1, 1],
    heading: 0
  });
  assert.equal(Spatial.containsPoint([-.5, .5], contour), true);
  assert.equal(Spatial.containsPoint([-.5, -.5], contour), false);
  assert.ok(Spatial.distanceFromContour([-.5, -.5], contour) > .49);
});
test('overlap uses union area instead of double counting blockers', () => {
  const square = [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1]
    ],
    left = [
      [-1, -1],
      [0, -1],
      [0, 1],
      [-1, 1]
    ];
  assert.equal(Spatial.coverageFraction(square, [left, left]), .5);
});
test('storage failure leaves account balance and unlocks unchanged', async () => {
  const account = new PlayerJournal({
    persist: async () => {
      throw new Error('Disk full');
    }
  });
  const before = account.inspect();
  await assert.rejects(account.openRound(1, 'a'), /Disk full/);
  assert.deepEqual(account.inspect(), before);
});
test('simultaneous duplicate reward callbacks create one credit', async () => {
  const account = new PlayerJournal();
  const results = await Promise.all([account.grantReceipt('receipt', 'scan'), account.grantReceipt('receipt', 'scan')]);
  assert.deepEqual(results, ['granted', 'duplicate']);
  assert.equal(account.inspect().credits.scan, 1);
});
test('rejected tool applications refund their credit', async () => {
  const account = new PlayerJournal();
  await account.grantReceipt('receipt', 'scan');
  assert.equal(await account.spend('scan', {
    apply: () => false
  }), false);
  assert.equal(account.inspect().credits.scan, 1);
});
test('concurrent tool application is rejected while the first is pending', async () => {
  const account = new PlayerJournal();
  await account.grantReceipt('one', 'scan');
  await account.grantReceipt('two', 'scan');
  let finish;
  const application = new Promise(resolve => finish = resolve);
  const first = account.spend('scan', {
    apply: () => application
  });
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(await account.spend('scan'), false);
  finish(true);
  assert.equal(await first, true);
  assert.equal(account.inspect().credits.scan, 1);
});
test('unfinished reward application survives a failed final save', async () => {
  let rejectSave = false;
  const account = new PlayerJournal({
    persist: async () => {
      if (rejectSave) throw new Error('Storage unavailable');
    }
  });
  await account.openRound(1, 'a');
  await account.grantReceipt('one', 'scan');
  const round = fresh();
  await assert.rejects(account.spend('scan', {
    snapshot: () => round.save(),
    apply: () => {
      rejectSave = true;
      return true;
    }
  }), /Storage unavailable/);
  assert.equal(account.inspect().attempt.pending.kind, 'scan');
  rejectSave = false;
  await assert.rejects(account.openRound(1, 'b'), /Reward recovery/);
  await account.recoverSpend(true, round.save());
  assert.equal(account.inspect().attempt.pending, null);
  assert.equal(account.inspect().credits.scan, 0);
});
test('power recovery preserves partial intervals and respects the cap', async () => {
  let clock = 0;
  const account = new PlayerJournal({
    clock: () => clock
  });
  await account.openRound(1, 'a');
  clock = 1799999;
  assert.equal(account.powerStatus().amount, 4);
  assert.equal(account.powerStatus().refillIn, 1);
  clock = 1800000;
  assert.equal(account.powerStatus().amount, 5);
  clock = 7200000;
  assert.equal(account.powerStatus().amount, 5);
});
test('a daylight-saving day can have 23 hours', () => {
  const calendar = new LocalCalendar('America/New_York'),
    day = calendar.dayNumber(Date.parse('2026-03-08T12:00:00Z'));
  assert.equal(calendar.midnight(day + 1) - calendar.midnight(day), 23 * 3600000);
});
test('collection rewards cannot be replayed with the same attempt', () => {
  const context = {
    stage: 5,
    first: true,
    attemptId: 'a',
    at: 1800000000000
  };
  const serial = nextCollectionPhoto(undefined, context),
    album = advanceCollection(undefined, {
      ...context,
      confirmed: serial
    });
  assert.equal(album.pages.length, 1);
  assert.deepEqual(advanceCollection(album, {
    ...context,
    confirmed: 2
  }), album);
});

test('a rejected stamina reward restores both power and credit', async () => {
  const account = new PlayerJournal({
    clock: () => 0
  });
  await account.openRound(1, 'a');
  await account.grantReceipt('one', 'stamina');
  assert.equal(account.powerStatus().amount, 4);
  assert.equal(await account.spend('stamina', {
    apply: () => false
  }), false);
  assert.equal(account.powerStatus().amount, 4);
  assert.equal(account.inspect().credits.stamina, 1);
});
test('a throwing tool callback refunds a credit without a round snapshot', async () => {
  const account = new PlayerJournal();
  await account.grantReceipt('one', 'scan');
  await assert.rejects(account.spend('scan', {
    apply: () => {
      throw new Error('Unable to apply');
    }
  }), /Unable to apply/);
  assert.equal(account.inspect().credits.scan, 1);
});

test('activity calendar stays pinned after restoring in another device zone', async () => {
  const {
    FestivalBook
  } = await import('../src/festivals.js');
  const clock = () => Date.parse('2026-11-01T04:30:00Z');
  const first = new FestivalBook({
    clock,
    zone: 'America/New_York'
  });
  const expected = first.seasonStatus();
  const restored = new FestivalBook({
    clock,
    zone: 'Asia/Tokyo',
    record: first.inspect()
  });
  assert.deepEqual(restored.seasonStatus(), expected);
  await first.settled();
  await restored.settled();
});
test('achievement calendar stays pinned after a saved profile is restored', async () => {
  const {
    MeritBook
  } = await import('../src/collections.js');
  const first = new MeritBook({
    zone: 'America/New_York'
  });
  const restored = new MeritBook({
    zone: 'Asia/Tokyo',
    record: first.inspect()
  });
  assert.equal(restored.inspect().zone, 'America/New_York');
});
