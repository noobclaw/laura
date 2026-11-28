import {
  SortingSession,
  readStage
} from '../src/index.js';
import { applyAmericanArt } from '../src/art.js';
import { resolvePose } from '../src/poses.js';
import {frameFor,viewTransform} from '../src/view.js';
const byId = id => document.getElementById(id),
  surface = byId('board'),
  paint = surface.getContext('2d');
let round, payload, pictures = new Map(),
  transform, eraseMode = false,
  previous = performance.now(),
  messageTimer, loadingTicket = 0;
const picker = byId('stage');
for (let number = 1; number <= 160; number++) picker.add(new Option(String(number), String(number)));
const picture = src => new Promise((resolve, reject) => {
  const image = new Image();
  image.onload = () => resolve(image);
  image.onerror = () => reject(new Error('Missing image'));
  image.src = src;
});

function inform(text) {
  byId('message').textContent = text;
  byId('message').classList.add('show');
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => byId('message').classList.remove('show'), 2000);
}
async function begin(number) {
  const ticket = ++loadingTicket;
  round = null;
  byId('phase').textContent = 'Loading…';
  document.querySelectorAll('button').forEach(button => button.disabled = true);
  const incoming = applyAmericanArt(await readStage(number));
  const paths = new Set([...Object.values(incoming.scene.sprites), incoming.scene.background]);
  const loaded = await Promise.all([...paths].map(async src => [src, await picture(src)]));
  if (ticket !== loadingTicket) return false;
  payload = incoming;
  pictures = new Map(loaded);
  round = new SortingSession(payload.stage, payload.forms);
  eraseMode = false;
  previous = performance.now();
  document.querySelectorAll('button').forEach(button => button.disabled = false);
  render();
  return true;
}

function act(action) {
  if (!round) return;
  const result = round.dispatch(action);
  const signals = round.takeSignals();
  for (const signal of signals) {
    if (signal.kind === 'selectionBlocked') inform('That object is covered');
    if (signal.kind === 'roundLost') inform('Tray full — expand a slot or return objects');
    if (signal.kind === 'roundCleared') inform('All requests completed');
  }
  render();
  return result;
}

function spriteFor(group) {
  const entry = payload.stage.specimens.find(entry => entry.group === group);
  return entry ? payload.scene.sprites[entry.form] : null;
}

function render() {
  if (!round) return;
  const state = round.inspect();
  byId('phase').textContent = {
    live: 'Playing',
    lost: 'Tray full',
    done: 'Complete'
  } [state.phase];
  byId('elapsed').textContent = `${Math.floor(state.seconds/60)}:${String(Math.floor(state.seconds%60)).padStart(2,'0')}`;
  byId('remaining').textContent = `${state.board.length} objects`;
  byId('bays').replaceChildren(...state.bays.slice(0, round.visibleBays).map((bay, index) => {
    const element = document.createElement(bay.available ? 'div' : 'button');
    element.className = 'bay' + (bay.available ? '' : ' locked');
    if (!bay.available) {
      element.textContent = '+ Request';
      element.onclick = () => act({
        kind: 'expandBay',
        bay: index
      });
    } else if (bay.group === -1) element.textContent = '✓';
    else {
      const image = document.createElement('img');
      image.src = spriteFor(bay.group);
      image.alt = '';
      const count = document.createElement('span');
      count.textContent = `${bay.filled}/${bay.required}`;
      element.append(image, count);
    }
    return element;
  }));
  byId('tray').replaceChildren(...state.tray.map(cell => {
    const element = document.createElement(cell.available ? 'div' : 'button');
    element.className = 'cell' + (cell.available ? '' : ' locked');
    if (!cell.available) {
      element.textContent = '+';
      element.onclick = () => act({
        kind: 'expandTray'
      });
    } else if (cell.tokenId !== null) {
      const entry = payload.stage.specimens[cell.tokenId],
        image = document.createElement('img');
      image.src = payload.scene.sprites[entry.form];
      image.alt = 'Stored object';
      element.append(image);
    }
    return element;
  }));
  document.querySelector('[data-action="eraseMode"]').classList.toggle('selected', eraseMode);
  draw();
}

function draw() {
  if (!round) return;
  const bounds = surface.getBoundingClientRect(),
    dpr = devicePixelRatio || 1;
  const width = Math.round(bounds.width * dpr),
    height = Math.round(bounds.height * dpr);
  if (surface.width !== width || surface.height !== height) {
    surface.width = width;
    surface.height = height;
  }
  paint.setTransform(dpr, 0, 0, dpr, 0, 0);
  paint.clearRect(0, 0, bounds.width, bounds.height);
  const [w,h]=payload.scene.extent,view=viewTransform(frameFor(payload),bounds.width,bounds.height),zoom=view.zoom;
  transform = {
    zoom,
    x: bounds.width/2-view.center[0]*zoom,
    y: bounds.height/2+view.center[1]*zoom
  };
  const background = pictures.get(payload.scene.background);
  paint.drawImage(background, transform.x - w * zoom / 2, transform.y - h * zoom / 2, w * zoom, h * zoom);
  const state = round.inspect();
  for (const id of state.board) {
    const raw=payload.stage.specimens[id], token=resolvePose(raw,payload.forms[raw.form],id),
      form = payload.forms[token.form],
      image = pictures.get(payload.scene.sprites[token.form]);
    paint.save();
    paint.translate(transform.x + token.at[0] * zoom, transform.y - token.at[1] * zoom);
    paint.rotate(-token.heading * Math.PI / 180);
    paint.scale(token.stretch[0] * zoom, token.stretch[1] * zoom);
    paint.drawImage(image, -form.extent[0] / 2, -form.extent[1] / 2, ...form.extent);
    const marked = state.promptToken === id || state.scanTokens.includes(id);
    if (marked || byId('outlines').checked) {
      paint.beginPath();
      for (let i = 0; i < form.outline.length; i++) {
        const point = form.outline[i];
        paint[i ? 'lineTo' : 'moveTo'](point[0], -point[1]);
      }
      paint.closePath();
      paint.lineWidth = (marked ? 4 : 1.3) / (zoom * Math.abs(token.stretch[0]));
      paint.strokeStyle = marked ? '#ffe563' : '#208c88';
      paint.stroke();
    }
    paint.restore();
  }
}
surface.addEventListener('pointerdown', event => {
  if (!round || !transform) return;
  const rect = surface.getBoundingClientRect(),
    point = [(event.clientX - rect.left - transform.x) / transform.zoom, -(event.clientY - rect.top - transform.y) / transform.zoom];
  if (eraseMode) {
    const chosen = round.locateErase(point);
    if (chosen !== null) {
      act({
        kind: 'erase',
        tokenId: chosen
      });
      eraseMode = false;
      render();
    }
  } else act({
    kind: 'pointer',
    point,
    radius: 12 / transform.zoom
  });
});
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => {
  const kind = button.dataset.action;
  if (kind === 'eraseMode') {
    eraseMode = !eraseMode;
    render();
    return;
  }
  if (kind === 'scan') {
    act({
      kind: 'scanGrant'
    });
    act({
      kind: 'scanActivate'
    });
    return;
  }
  act({
    kind
  });
}));
picker.onchange = () => begin(Number(picker.value)).catch(error => inform(error.message));
byId('restart').onclick = () => begin(Number(picker.value));
byId('save').onclick = () => {
  if (!round) return;
  localStorage.setItem('sorting-lab-checkpoint', JSON.stringify({
    number: Number(picker.value),
    snapshot: round.save()
  }));
  inform('Saved');
};
byId('restore').onclick = async () => {
  try {
    const saved = JSON.parse(localStorage.getItem('sorting-lab-checkpoint'));
    if (!saved) return inform('No saved round');
    picker.value = String(saved.number);
    if (!await begin(saved.number)) return;
    round = SortingSession.resume(payload.stage, payload.forms, saved.snapshot);
    render();
    inform('Restored');
  } catch (error) {
    inform(error.message);
  }
};
byId('outlines').onchange = draw;
new ResizeObserver(draw).observe(surface);

function frame(at) {
  if (round) {
    const elapsed = Math.max(0, Math.min(0.25, (at - previous) / 1000));
    round.dispatch({
      kind: 'advance',
      seconds: elapsed
    });
    round.takeSignals();
    byId('elapsed').textContent = `${Math.floor(round.inspect().seconds/60)}:${String(Math.floor(round.inspect().seconds%60)).padStart(2,'0')}`;
    draw();
  }
  previous = at;
  requestAnimationFrame(frame);
}
await begin(1);
requestAnimationFrame(frame);
