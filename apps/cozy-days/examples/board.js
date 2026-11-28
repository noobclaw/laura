import { resolvePose } from '../src/poses.js';
import {frameFor,viewTransform} from '../src/view.js';
export async function loadPictures(payload) {
  const paths = new Set([...Object.values(payload.scene.sprites), payload.scene.background]);
  return new Map(await Promise.all([...paths].map(src => new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve([src, image]);
    image.onerror = () => reject(new Error('Image unavailable'));
    image.src = src;
  }))));
}

export function attachBoard(canvas, { payload, pictures, currentRound, onPick, label }) {
  const paint = canvas.getContext('2d');
  let transform, focusToken = null;
  function draw() {
    const round = currentRound();
    if (!round || !canvas.isConnected) return;
    const bounds = canvas.getBoundingClientRect(), dpr = devicePixelRatio || 1;
    if (!bounds.width || !bounds.height) return;
    if (canvas.width !== Math.round(bounds.width * dpr) || canvas.height !== Math.round(bounds.height * dpr)) {
      canvas.width = Math.round(bounds.width * dpr);
      canvas.height = Math.round(bounds.height * dpr);
    }
    paint.setTransform(dpr, 0, 0, dpr, 0, 0);
    paint.clearRect(0, 0, bounds.width, bounds.height);
    const [w,h]=payload.scene.extent,view=viewTransform(frameFor(payload),bounds.width,bounds.height),zoom=view.zoom;
    transform={zoom,x:bounds.width/2-view.center[0]*zoom,y:bounds.height/2+view.center[1]*zoom};
    paint.fillStyle='#c49b65';paint.fillRect(0,0,bounds.width,bounds.height);
    paint.drawImage(pictures.get(payload.scene.background), transform.x - w * zoom / 2, transform.y - h * zoom / 2, w * zoom, h * zoom);
    const state = round.inspect();
    for (const id of state.board) {
      const raw=payload.stage.specimens[id],form=payload.forms[raw.form],token=resolvePose(raw,form,id);
      paint.save();
      paint.translate(transform.x + token.at[0] * zoom, transform.y - token.at[1] * zoom);
      paint.rotate(-token.heading * Math.PI / 180);
      paint.scale(token.stretch[0] * zoom, token.stretch[1] * zoom);
      paint.drawImage(pictures.get(payload.scene.sprites[token.form]), -form.extent[0] / 2, -form.extent[1] / 2, ...form.extent);
      if (state.promptToken === id || state.scanTokens.includes(id) || focusToken === id) {
        paint.beginPath();
        form.outline.forEach(([x, y], i) => paint[i ? 'lineTo' : 'moveTo'](x, -y));
        paint.closePath();
        paint.lineWidth = 3 / (zoom * Math.abs(token.stretch[0]));
        paint.strokeStyle = focusToken === id ? '#ffffff' : '#ffdd63';
        paint.shadowColor = '#634d13'; paint.shadowBlur = 4;
        paint.stroke();
      }
      paint.restore();
    }
  }
  canvas.addEventListener('pointerdown', event => {
    if (!transform) return;
    const rect = canvas.getBoundingClientRect();
    onPick([(event.clientX - rect.left - transform.x) / transform.zoom, -(event.clientY - rect.top - transform.y) / transform.zoom], 12 / transform.zoom);
  });
  canvas.addEventListener('keydown', event => {
    const round = currentRound();
    if (!round || !['ArrowRight', 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'Enter', ' '].includes(event.key)) return;
    event.preventDefault();
    const choices = round.inspect().board.filter(id => !round.isObstructed(id));
    if (!choices.length) return;
    if (['Enter', ' '].includes(event.key)) {
      const id = choices.includes(focusToken) ? focusToken : choices[0];
      onPick(round.tokenInfo(id).at, 0, id);
    } else {
      const step = ['ArrowLeft', 'ArrowUp'].includes(event.key) ? -1 : 1;
      const index = choices.indexOf(focusToken);
      focusToken = choices[index < 0 ? (step > 0 ? 0 : choices.length - 1) : (index + step + choices.length) % choices.length];
      canvas.setAttribute('aria-label', `${label} · ${choices.indexOf(focusToken) + 1}/${choices.length}`);
    }
    draw();
  });
  const observer = new ResizeObserver(draw);
  observer.observe(canvas);
  draw();
  return { draw, dispose: () => observer.disconnect() };
}
