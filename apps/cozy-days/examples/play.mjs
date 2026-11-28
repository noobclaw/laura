import {
  readFile
} from 'node:fs/promises';
import {
  SortingSession,
  readStage
} from '../src/index.js';
const number = Number(process.argv[2] ?? 1);
const {
  stage,
  forms
} = await readStage(number, async url => JSON.parse(await readFile(url, 'utf8')));
let session = new SortingSession(stage, forms);
session.dispatch({
  kind: 'advance',
  seconds: 30
});
session = SortingSession.resume(stage, forms, session.save());
for (let i = 0; i < stage.shipments.length + 4 && session.inspect().phase === 'live'; i++) session.dispatch({
  kind: 'sweepBay'
});
const result = session.inspect();
console.log(JSON.stringify({
  stage: number,
  phase: result.phase,
  seconds: result.seconds,
  remaining: result.board.length,
  signals: session.takeSignals().length
}, null, 2));
if (result.phase !== 'done') process.exitCode = 1;
