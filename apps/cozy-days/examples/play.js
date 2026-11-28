import { restoreSavedGame } from '../src/save-recovery.js';
import {
  Playthrough
} from '../src/playthrough.js?v=0.2.0';
import {
  readCampaignStage,
  CAMPAIGN_EDITION,
  toolUnlock
} from '../src/campaign.js';
import {
  shopProducts,
  productPresentation
} from '../src/shop.js';
import { requestLabel, requestPictures, requestExamples } from '../src/requests.js';
import {
  meritCatalog
} from '../src/collections.js?v=0.2.0';
import {
  RivalField
} from '../src/opponents.js';
import {
  translator,
  meritTitle
} from './strings.js?v=0.2.0-2';
import {
  loadPictures
} from './board.js?v=0.2.0';
import {
  attachThreeBoard,
  attachPacking
} from '../web/scenes.jsx';
import {
  icon
} from './icons.js';
import { applyAmericanArt, newArt } from '../src/art.js';
import {
  sound,
  fly,
  pop,
  celebrate,
  cleanupFeedback,
  finishBox,
  praise,
  boardFeedback,
  motionAllowed
} from './feedback.js';

const byId = id => document.getElementById(id);
const content = byId('content'),
  modal = byId('modal');
const SAVE_KEY = 'sorting-playthrough-v1';
// First launch follows the system language; unsupported languages fall back to English.
const systemLocale = () => {
  for (const tag of navigator.languages ?? [navigator.language]) {
    const lower = String(tag).toLowerCase();
    if (/^zh-(tw|hk|mo|hant)/.test(lower)) return 'zh-TW';
    if (lower.startsWith('zh')) return 'zh-CN';
    if (lower.startsWith('en')) return 'en';
  }
  return 'en';
};
let locale = localStorage.getItem('sorting-language') ?? systemLocale();
if (!['zh-CN', 'zh-TW', 'en'].includes(locale)) locale = systemLocale();
document.documentElement.lang = locale;
let t = translator(locale),
  view = 'home',
  uiBusy = false,
  board, packing, builtAttempt, eraseMode = false;
let cachedRaw = localStorage.getItem(SAVE_KEY),
  game,
  toastTimer;
let collectionStreak = 0, lastCollectionAt = 0;
const assets = new Map(),
  stageCache = new Map();
const clockText = value => {
  const seconds = Math.max(0, Math.ceil(value));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
};
const remainingTime = end => {
  const seconds = Math.max(0, Math.ceil((end - Date.now()) / 1000));
  return seconds < 3600 ? clockText(seconds) : `${Math.floor(seconds / 3600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
};
const el = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function button(text, handler, className = 'secondary') {
  const node = el('button', className, text);
  node.type = 'button';
  node.onclick = () => {
    if (!uiBusy) handler();
  };
  return node;
}

function toast(message) {
  byId('toast').textContent = message;
  byId('toast').classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => byId('toast').classList.remove('show'), 3500);
}

function dialog(title, message, actions = []) {
  modal.className = '';
  delete modal.dataset.kind;
  const box = byId('modal-content');
  box.replaceChildren(el('h2', '', title));
  box.firstChild.id = 'modal-title';
  if (message) box.append(el('p', '', message));
  if (actions.length) {
    const row = el('div', 'row');
    actions.forEach(([label, callback, style]) => row.append(button(label, () => {
      modal.close();
      callback();
    }, style)));
    box.append(row);
  }
  byId('modal-close').textContent = t('close');
  if (!modal.open) modal.showModal();
}
async function task(operation) {
  if (uiBusy) return;
  uiBusy = true;
  byId('app').setAttribute('aria-busy', 'true');
  try {
    await operation();
    await renderCurrent();
    byId('save-status').textContent = t('local');
  } catch (error) {
    console.error('Playthrough action failed', error);
    dialog(t('saveFailed'), t('saveError'), [
      [t('reload'), () => window.location.reload(), 'primary']
    ]);
    // The coordinator keeps the previous committed state on failure.
    if (view === 'game' && byId('play-board')) updateGame();
  } finally {
    uiBusy = false;
    byId('app').removeAttribute('aria-busy');
  }
}
async function loadStage(number, {
  edition = CAMPAIGN_EDITION
} = {}) {
  const key = `${edition}:${number}`;
  if (!stageCache.has(key)) stageCache.set(key, applyAmericanArt(await readCampaignStage(number, {
    edition
  })));
  return stageCache.get(key);
}
async function prepare(number, restart = false) {
  const active = game.inspect().player.attempt;
  const payload = !restart && active?.number === number ? game.payload : await loadStage(number);
  assets.set(number, await loadPictures(payload));
}

function header() {
  const player = game.inspect().player,
    power = game.powerStatus();
  meter('power', 'heart', `${power.amount}/${power.capacity}`, t('energy', {
    n: power.amount,
    max: power.capacity
  }));
  const stars = Object.values(player.ratings).reduce((sum, n) => sum + n, 0);
  meter('stars', 'star', String(stars), t('totalStars', {
    n: stars
  }));
  byId('lab-link').textContent = t('lab');
  byId('save-status').textContent = t('local');
  byId('language').value = locale;
  document.documentElement.lang = locale;
  byId('navigation').replaceChildren(...['home', 'album', 'merits', 'events', 'ranking'].map(name => {
    const node = button('', () => task(async () => {
      await game.save();
      disposeBoard();
      view = name;
      eraseMode = false;
      window.scrollTo({
        top: 0
      });
      content.scrollTop = 0;
    }), '');
    node.append(icon(name), el('span', 'nav-label', t(name)));
    node.setAttribute('aria-label', t(name));
    if (view === name || (name === 'home' && ['game', 'result'].includes(view))) node.setAttribute('aria-current', 'page');
    return node;
  }));
}

function meter(id, glyph, value, label) {
  const node = byId(id);
  if (!node.querySelector('strong')) node.replaceChildren(icon(glyph), el('strong'));
  node.querySelector('strong').textContent = value;
  node.setAttribute('aria-label', label);
  node.title = label;
}

function disposeBoard() {
  collectionStreak = 0; lastCollectionAt = 0;
  cleanupFeedback();
  board?.dispose();
  packing?.dispose();
  board = null;
  packing = null;
  builtAttempt = null;
}

function screenTitle(key, description) {
  content.replaceChildren(el('h1', '', t(key)), el('p', 'screen-intro', t(description)));
}

function home() {
  disposeBoard();
  const player = game.inspect().player;
  const scene = el('section', 'home-scene');
  const title = el('h1', 'game-logo');
  title.append(el('span', '', 'COZY'), el('span', '', 'DAYS'));
  const subtitle = el('p', 'world-name', t('townName'));
  const number = player.attempt?.number ?? player.cursor;
  const play = button('', () => openRound(number), 'play-button');
  const playText = el('span', 'play-label', t(player.attempt ? 'continue' : 'startGame'));
  const next = el('small', 'play-level', t('level', {
    n: number
  }));
  const arrow = icon('play');
  play.append(arrow, playText, next);
  const map = button('', openMap, 'scene-shortcut map-shortcut');
  map.append(icon('map'), el('span', '', t('stages')));
  map.setAttribute('aria-label', t('stages'));
  const album = button('', () => task(async () => {
    disposeBoard();
    view = 'album';
  }), 'scene-shortcut album-shortcut');
  album.append(icon('album'), el('span', '', t('album')));
  const albumBadge = el('small', 'shortcut-badge', player.frontier < 5 ? t('locked', {
    n: 5
  }) : `${game.albumStatus().count}/48`);
  album.append(albumBadge);
  const events = button('', () => task(async () => {
    disposeBoard();
    view = 'events';
  }), 'scene-shortcut event-shortcut');
  events.append(icon('events'), el('span', '', t('events')), el('small', 'shortcut-badge', player.frontier < 12 ? t('locked', {
    n: 12
  }) : t('raceReady')));
  const toys = el('div', 'packing-view');
  toys.tabIndex = 0;
  toys.setAttribute('role', 'img');
  const progress = el('div', 'journey-pill', t('progress', {
    n: Object.keys(player.ratings).length
  }));
  const light = el('div', 'scene-motes');
  light.setAttribute('aria-hidden', 'true');
  for (let i = 0; i < 7; i++) light.append(el('i'));
  scene.append(light, title, subtitle, album, events, map, toys, play, progress);
  content.replaceChildren(scene);
  packing = attachPacking(toys,{onToss:()=>sound('box')});
}

function openMap() {
  const player = game.inspect().player;
  dialog(t('stages'), t('progress', {
    n: Object.keys(player.ratings).length
  }));
  modal.classList.add('map-dialog');
  const scroll = el('div', 'map-scroll'),
    trail = el('div', 'level-map');
  const pattern = [25, 52, 76, 62, 35, 17, 38, 66],
    rowHeight = 80;
  trail.style.height = `${160*rowHeight+50}px`;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 100 ${160*20+20}`);
  svg.setAttribute('preserveAspectRatio', 'none');
  svg.classList.add('map-road');
  const path = document.createElementNS(svg.namespaceURI, 'path');
  path.setAttribute('d', Array.from({
    length: 160
  }, (_, i) => `${i?'L':'M'}${pattern[i%pattern.length]} ${i*20+13}`).join(' '));
  svg.append(path);
  trail.append(svg);
  for (let number = 1; number <= 160; number++) {
    const rating = player.ratings[number] ?? 0;
    const node = button('', () => {
      modal.close();
      openRound(number);
    }, `level-tile${rating?' cleared':''}${number===player.frontier?' current':''}`);
    node.dataset.level = number;
    node.style.left = `${pattern[(number-1)%pattern.length]}%`;
    node.style.top = `${(number-1)*rowHeight+20}px`;
    if (number > player.frontier) node.append(icon('lock'));
    else node.append(el('strong', '', String(number)));
    const stars = el('small', 'map-stars');
    for (let i = 0; i < 3; i++) {
      const star = icon('star');
      if (i >= rating) star.classList.add('unearned');
      stars.append(star);
    }
    node.append(stars);
    node.disabled = number > player.frontier;
    node.setAttribute('aria-label', `${t('level', { n: number })} · ${rating}/3`);
    trail.append(node);
  }
  scroll.append(trail);
  byId('modal-content').append(scroll);
  scroll.scrollTop = Math.max(0, (player.frontier - 1) * rowHeight - 120);
}

function openRound(number, restart = false) {
  task(async () => {
    await prepare(number, restart);
    const status = await game.start(number, {
      restart
    });
    if (status === 'energy') return dialog(t('energy', {
      n: game.powerStatus().amount,
      max: game.powerStatus().capacity
    }), t('noEnergy'));
    if (status === 'locked') return toast(t('locked', {
      n: number
    }));
    disposeBoard();
    view = 'game';
    eraseMode = false;
    window.scrollTo({
      top: 0
    });
  });
}

function restartDialog() {
  dialog(t('retry'), t('confirmRestart'), [
    [t('retry'), () => openRound(game.number, true), 'primary']
  ]);
}

function pauseDialog() {
  const power=game.powerStatus(),stars=Object.values(game.inspect().player.ratings).reduce((sum,n)=>sum+n,0);
  dialog(t('paused'), `${t('energy',{n:power.amount,max:power.capacity})} · ${t('totalStars',{n:stars})}`, [
    [t('resume'), () => {}, 'primary'],
    [t('back'), () => task(async () => {
      await game.save();
      disposeBoard();
      view = 'home';
    })],
    [t('retry'), restartDialog],
    [t('shop'),()=>openShop()],
    [t('settings'),()=>byId('settings').click()]
  ]);
}

function makeGame() {
  const run = game.inspect().player.attempt;
  if (!run) {
    view = 'result';
    return resultScreen();
  }
  if (builtAttempt === run.attemptId && board) return updateGame();
  disposeBoard();
  const section = el('section', 'game');
  const heading = el('div', 'game-head');
  const pause = button('', pauseDialog, 'round-button');
  pause.append(icon('pause'));
  pause.setAttribute('aria-label', t('pause'));
  const badge=el('h2','stage-badge');badge.setAttribute('aria-label',t('level',{n:run.number}));badge.append(el('small','',t('stageLabel')),el('strong','',String(run.number)));
  heading.append(badge,pause);
  const status = el('div', 'game-status');
  for (const id of ['play-phase', 'play-time', 'play-left']) {
    const item = el('span');
    item.id = id;
    status.append(item);
  }
  const bays = el('section', 'bays');
  bays.id = 'play-bays';
  bays.setAttribute('aria-label', t('request'));
  const wrapper = el('div', 'board'),
    canvas = el('div');
  canvas.id = 'play-board';
  canvas.tabIndex = 0;
  canvas.setAttribute('role', 'application');
  canvas.setAttribute('aria-label', t('intro'));
  const zoom = button('', () => {
    const scale = board?.toggleZoom();
    zoom.setAttribute('aria-label', t(scale > 1 ? 'zoomOut' : 'zoomIn'));
    zoom.setAttribute('aria-pressed', String(scale > 1));
    if (scale > 1) toast(t('dragToLook'));
  }, 'board-zoom');
  zoom.append(icon('scan'));
  zoom.setAttribute('aria-label', t('zoomIn'));
  zoom.setAttribute('aria-pressed', 'false');
  wrapper.append(canvas, zoom);
  const tray = el('section', 'tray');
  tray.id = 'play-tray';
  tray.setAttribute('aria-label', t('tray'));
  const tools = el('div', 'tools');
  tools.id = 'play-tools';
  const tip = el('div', 'board-tip', t('firstGoal'));
  tip.hidden = run.number > 2;
  wrapper.append(tip);
  const criteria = el('p', 'criteria', t('criteria', {
    fast: clockText(game.payload.stage.rating?.fast ?? game.payload.stage.specimens.length * 3),
    medium: clockText(game.payload.stage.rating?.medium ?? game.payload.stage.specimens.length * 5)
  }));
  const help = el('p', 'game-help', t(run.number < 3 ? 'lockedTools' : 'toolNote'));
  const loss = el('div');
  loss.id = 'play-loss';
  section.append(heading, status, bays, wrapper, tray, tools, criteria, help, loss);
  content.replaceChildren(section);
  board = attachThreeBoard(canvas, {
    payload: game.payload,
    pictures: assets.get(run.number),
    currentRound: () => game.round,
    label: t('intro'),
    onPick: (point, radius, tokenId) => {
      if (uiBusy || modal.open || canvas.dataset.graphics === 'lost') return;
      task(async () => {
        if (eraseMode) {
          const id = tokenId ?? game.round.locateErase(point);
          if (id === null) return;
          await applyTool('rub', id);
          eraseMode = false;
        } else showSignals(await game.move(tokenId === undefined ? {
          kind: 'pointer',
          point,
          radius,
          preference: 'visible'
        } : {
          kind: 'collect',
          tokenId
        }));
        if (game.round?.inspect().phase === 'done') {
          updateGame();
          await new Promise(resolve => setTimeout(resolve, motionAllowed() ? 430 : 0));
        }
      });
    }
  });
  builtAttempt = run.attemptId;
  updateGame();
}

function showRequest(group) {
  const name = requestLabel(group, locale);
  dialog(name, t('requestContents'));
  const gallery = el('div', 'request-gallery');
  for (const path of requestPictures(game.payload, group)) {
    const image = el('img'); image.src = path; image.alt = name;
    gallery.append(image);
  }
  byId('modal-content').append(gallery);
}

function updateGame() {
  if (!game.round || !byId('play-bays')) return;
  const state = game.round.inspect(),
    number = game.number;
  byId('play-phase').textContent = t(state.phase === 'live' ? 'playing' : state.phase === 'lost' ? 'lost' : 'done');
  byId('play-time').textContent = clockText(state.seconds);
  byId('play-left').textContent = t('objects', {
    n: state.board.length
  });
  byId('play-bays').replaceChildren(...state.bays.slice(0, game.round.visibleBays).map(bay => {
    if (!bay.available) {
      const locked = button('', () => task(() => applyTool('bay')), 'bay locked');
      locked.append(icon('lock'));
      locked.setAttribute('aria-label', t('request'));
      return locked;
    }
    const node = bay.group === -1 ? el('div', 'bay') : button('', () => showRequest(bay.group), 'bay request-category');
    node.dataset.feedbackKey = `bay-${state.bays.indexOf(bay)}`;
    if (bay.group === -1) node.textContent = '✓';
    else {
      const name = requestLabel(bay.group, locale), pictures = requestPictures(game.payload, bay.group);
      const examples = el('span', 'request-examples');
      for (const path of requestExamples(pictures)) {
        const image = el('img'); image.src = path; image.alt = '';
        examples.append(image);
      }
      const count = `${bay.filled}/${bay.required}`;
      node.append(examples, el('span', 'request-count', count), el('span', 'request-name', name));
      node.setAttribute('aria-label', `${name} ${count} · ${t('requestDetails')}`);
      node.title = `${name} · ${t('requestDetails')}`;
      node.style.setProperty('--filled', `${bay.filled/bay.required*100}%`);
    }
    return node;
  }));
  byId('play-tray').replaceChildren(...state.tray.map(cell => {
    if (!cell.available) {
      const node = button('+', () => task(() => applyTool('tray')), 'cell locked');
      node.setAttribute('aria-label', t('tray'));
      return node;
    }
    const node = el('div', 'cell');
    node.dataset.feedbackKey = `tray-${state.tray.indexOf(cell)}`;
    if (cell.tokenId !== null) {
      const image = el('img');
      image.src = game.payload.scene.sprites[game.payload.stage.specimens[cell.tokenId].form];
      image.alt = '';
      node.append(image);
    }
    return node;
  }));
  byId('play-tools').replaceChildren(...['sweep', 'return', 'scan', 'rub'].map(kind => {
    const node = button('', () => {
      if (kind === 'rub' && number >= toolUnlock(kind, game.inspect().roundEdition ?? 'classic') && game.wallet(kind) > 0 && state.phase === 'live') {
        eraseMode = !eraseMode;
        updateGame();
        if (eraseMode) toast(t('selectedErase'));
        return;
      }
      task(() => applyTool(kind));
    }, eraseMode && kind === 'rub' ? 'selected' : '');
    const unlock = toolUnlock(kind, game.inspect().roundEdition ?? 'classic');
    const count = kind === 'scan' && ((state.scanCredits ?? 0) > 0 || state.scanTokens.length) ? (state.scanCredits ?? 0) + state.scanTokens.length : game.wallet(kind);
    node.append(icon(kind), el('b', 'tool-count', number < unlock ? String(unlock) : String(count)), el('span', '', t(`${kind}Short`)));
    node.title = t(kind);
    if (number < unlock) node.append(icon('lock'));
    node.dataset.tool = kind;
    node.setAttribute('aria-label',`${t(kind)} · ${number<unlock?t('locked',{n:unlock}):count}`);
    node.disabled = number < unlock || state.phase === 'done';
    return node;
  }));
  const loss = byId('play-loss');
  loss.replaceChildren();
  if (state.phase === 'lost') {
    const box = el('div', 'lost-card');
    box.append(el('h3', '', t('lost')), el('p', 'game-help', t('toolNote')),
      button(t('retry'), restartDialog), button(t('back'), () => task(async () => {
        await game.save();
        disposeBoard();
        view = 'home';
      })));
    loss.append(box);
  }
  const tip = content.querySelector('.board-tip');
  if (tip) tip.hidden = number > 2 || state.board.length < game.payload.stage.specimens.length - 2;
  board?.draw();
}

function showSignals(signals = []) {
  if (signals.some(signal => ['selectionBlocked','trayStored','selectionReversed','trayReturned','tokenErased'].includes(signal.kind))) collectionStreak = 0;
  if (signals.some(signal => signal.kind === 'boardDelivered')) {
    const now = performance.now();
    collectionStreak = now-lastCollectionAt < 5000 ? collectionStreak+1 : 1;
    lastCollectionAt = now;
    if ([3,5,8].includes(collectionStreak)) praise(byId('play-board'), t('collectionStreak',{n:collectionStreak}));
  }
  if (signals.some(signal => signal.kind === 'selectionBlocked')) {
    boardFeedback(byId('play-board'), 'blocked');
    toast(t('blocked'));
    sound('blocked');
  }
  for (const signal of signals) {
    if (!['boardDelivered', 'trayStored', 'trayDelivered'].includes(signal.kind)) continue;
    const token = game.payload.stage.specimens[signal.tokenId];
    const key = signal.kind === 'trayStored' ? `tray-${signal.cell}` : `bay-${signal.bay}`;
    const target = document.querySelector(`[data-feedback-key="${key}"]`);
    let from = board?.project(signal.tokenId);
    if (signal.kind === 'trayDelivered') {
      const cell = document.querySelector(`[data-feedback-key="tray-${signal.cell}"]`),
        r = cell?.getBoundingClientRect();
      if (r) from = {
        x: r.left + r.width / 2,
        y: r.top + r.height / 2,
        size: r.width
      };
    }
    fly(game.payload.scene.sprites[token.form], from, target);
    board?.burst(signal.tokenId, signals.some(item => item.kind === 'bayCompleted'));
    const material=/glass|bottle|metal|key|can|coin|tool/i.test(requestLabel(token.group,'en'))?'metal':'soft';
    sound('pickup',material);
  }
  if (signals.some(signal => signal.kind === 'bayCompleted')) {
    sound('box');
    for (const item of signals.filter(item => item.kind === 'bayCompleted')) finishBox(`bay-${item.bay}`);
  }
  for (const signal of signals) {
    if (signal.kind==='tokenErased') board?.burst(signal.tokenId,true);
    if (['scanHighlighted','scanFocused','trayReturned','selectionReversed','tokenErased'].includes(signal.kind)) {
      boardFeedback(byId('play-board'),'tool');sound('tool');
    }
  }
}
async function applyTool(kind, id) {
  const response = await game.use(kind, id);
  if (response.status === 'empty') {
    if (game.inspect().player.frontier >= 5) openShop(kind);
    else dialog(t(kind === 'bay' ? 'request' : kind === 'tray' ? 'tray' : kind), t('noCredit'));
  } else if (response.status === 'locked') toast(t('locked', {
    n: toolUnlock(kind, game.inspect().roundEdition ?? 'classic')
  }));
  else if (response.status === 'unavailable') toast(t('unavailable'));
  else {
    showSignals(response.signals);
    if (kind === 'scan') toast(t('introScan'));
  }
}

function photoImage(serial) {
  const image = el('div', 'photo-image story-photo');
  const rooms=['laundry','garage','kitchen','porch','studio','playroom','market','garden'];
  const room=rooms[Math.floor((serial-1)/6)], moment=(serial-1)%6;
  image.style.backgroundImage=`url("${newArt.rooms[room].path}")`;
  image.style.backgroundPosition=`${25+moment*10}% 30%`;
  const stories={laundry:['Tops','Towels','School Bags','Hats','Shoes','Gloves'],garage:['Tools','Sports Gear','Tape Measures','Flashlights','Car Keys','Buckets'],kitchen:['Fruit','Cups','Bread','Seasonings','Cooking Pots','Cookies'],porch:['Storage Baskets','Cushions','Books','Cups','Scarves','Umbrellas'],studio:['PC Accessories','Notebooks','Desk Lamps','Pens','Cameras','Folders'],playroom:['Plush Toys','Toy Vehicles','Blocks','Puzzle Cubes','Game Pieces','Dolls'],market:['Paper Bags','Boxes','Fruit','Gift Boxes','Tote Bags','Wallets'],garden:['Potted Plants','Empty Flower Pots','Flower Baskets','garden watering cans','garden hand trowels','Pumpkins']};
  for (let i=0;i<3;i++) {
    const art=Object.values(newArt.items).find(x=>x.category===stories[room][(moment+i)%6]);
    if (!art) continue;
    const item=el('img','story-prop');item.src=art.path;item.alt='';
    item.style.left=`${16+i*29}%`;item.style.bottom=`${8+(i%2)*9}%`;
    image.append(item);
  }
  image.setAttribute('role', 'img');
  image.setAttribute('aria-label', t('photo', {
    n: serial
  }));
  return image;
}

function resultScreen() {
  disposeBoard();
  const result = game.inspect().result;
  if (!result) {
    view = 'home';
    return home();
  }
  const box = el('section', 'result');
  const stars = el('div', 'result-stars');
  for (let i = 0; i < 3; i++) {
    const star = icon('star');
    if (i >= result.stars) star.classList.add('unearned');
    stars.append(star);
  }
  box.append(el('p', 'eyebrow', t('level', {
      n: result.number
    })), el('h1', '', t('done')),
    stars,
    el('p', '', t('resultTime', {
      time: clockText(result.seconds)
    })), el('p', 'muted', t('best', {
      time: clockText(result.best)
    })));
  if (result.photo) {
    const photo = el('div', 'new-photo');
    photo.append(photoImage(result.photo), el('small', '', t('newPhoto', {
      n: result.photo
    })));
    box.append(photo);
  }
  const actions = el('div', 'row');
  if (result.number < 160) actions.append(button(t('next'), () => openRound(result.next), 'primary'));
  else box.append(el('p', '', t('allDone')));
  actions.append(button(t('retry'), () => openRound(result.number, true)), button(t('back'), () => task(async () => {
    view = 'home';
  })));
  box.append(actions);
  content.replaceChildren(box);
  celebrate(box);
}

function albumScreen() {
  screenTitle('album', 'albumInfo');
  const record = game.inspect(),
    album = game.albumStatus();
  if (record.player.frontier < 5) content.append(el('div', 'lock-banner', t('locked', {
    n: 5
  })));
  content.append(el('p', 'rank-summary', t('albumProgress', {
    n: album.count,
    points: album.points
  })));
  for (let page = 0; page < 8; page++) {
    content.append(el('h3', '', t('page', {
      n: page + 1
    })));
    const grid = el('div', 'album-grid');
    for (let index = 0; index < 6; index++) {
      const serial = page * 6 + index + 1,
        collected = album.pages.find(entry => entry.serial === serial);
      const node = button('', () => task(async () => {
        await game.readPhoto(serial);
        dialog(t('photo', {
          n: serial
        }), '');
        byId('modal-content').append(photoImage(serial));
      }), 'photo-card');
      node.disabled = !collected;
      const image = collected ? photoImage(serial) : el('div', 'photo-image');
      if (!collected) image.append(icon('lock'));
      node.append(image, el('span', '', `${t('photo', { n: serial })}${collected && !collected.read ? ' · NEW' : ''}`));
      grid.append(node);
    }
    content.append(grid);
  }
}

function meritsScreen() {
  screenTitle('merits', 'achievementInfo');
  const facts = game.facts(),
    grid = el('div', 'achievement-grid');
  for (const {
      key,
      metric,
      target
    }
    of meritCatalog()) {
    const value = Math.min(target, Number(facts[metric] ?? 0)),
      complete = value >= target;
    const card = el('div', `achievement${complete ? ' complete' : ''}`),
      copy = el('div');
    copy.append(el('h3', '', meritTitle(key, locale)), el('small', '', complete ? `✓ ${t('earned')}` : `${value}/${target}`));
    const progress = el('progress');
    progress.max = target;
    progress.value = value;
    progress.setAttribute('aria-label', copy.firstChild.textContent);
    copy.append(progress);
    const badge = el('div', 'badge');
    badge.append(icon('merits'));
    card.append(badge, copy);
    grid.append(card);
  }
  content.append(grid);
}

function standingTable(rows, scoreKey = 'score') {
  const table = el('table', 'standings'),
    head = el('tr');
  ['rank', 'player', scoreKey === 'score' ? 'points' : 'score'].forEach(key => head.append(el('th', '', t(key))));
  const thead = el('thead');
  thead.append(head);
  table.append(thead);
  const body = el('tbody');
  rows.forEach(row => {
    const tr = el('tr', row.self ? 'self' : '');
    tr.append(el('td', '', String(row.position ?? row.rank)), el('td', '', row.self ? t('you') : `Neighbor ${String(row.identity ?? row.id).padStart(4, '0')}`), el('td', '', String(row[scoreKey])));
    body.append(tr);
  });
  table.append(body);
  return table;
}
async function eventsScreen() {
  screenTitle('events', 'eventInfo');
  const status = await game.eventsStatus();
  if (status.locked) {
    content.append(el('div', 'lock-banner', t('locked', {
      n: 12
    })));
    return;
  }
  const race = el('section', 'event-card'),
    top = el('div', 'event-top');
  top.append(el('h3', '', t('sprint')), el('small', '', t('starts', {
    n: status.starts
  })));
  race.append(top, el('p', '', t('raceInfo')));
  if (status.sprint) {
    const sprint = status.sprint;
    race.append(el('p', '', `${sprint.score}/30 · ${t('ends', { time: remainingTime(sprint.end) })}`), standingTable(sprint.table));
    if (sprint.final) {
      const claim = button(t(sprint.claimed ? 'claimed' : 'claim'), () => claimEvent('sprint'), 'primary');
      claim.disabled = sprint.claimed;
      race.append(claim);
    }
  }
  if (status.canEnter) race.append(button(t('enterRace'), () => task(async () => {
    await game.enterSprint();
  }), 'primary'));
  content.append(race);
  const league = el('section', 'event-card'),
    season = status.season;
  league.append(el('h3', '', t('season')), el('p', '', t('leagueInfo')),
    el('p', '', t('leagueStats', {
      tier: season.tier + 1,
      score: season.weeklyScore,
      rank: season.position
    })), el('p', 'muted', t('ends', {
      time: remainingTime(season.end)
    })));
  const milestones = el('div', 'milestones');
  season.milestones.forEach((milestone, index) => {
    const node = button(`${t('milestone', { n: milestone.threshold, power: milestone.power })} · ${t(milestone.claimed ? 'claimed' : 'claim')}`, () => claimEvent('checkpoint', index));
    node.disabled = !milestone.reached || milestone.claimed;
    milestones.append(node);
  });
  league.append(milestones, standingTable(season.table));
  content.append(league);
  if (status.pending) {
    const old = el('section', 'event-card');
    old.append(el('h3', '', t('lastSeason', {
      rank: status.pending.position
    })), button(t('claim'), () => claimEvent('season', status.pending.begin), 'primary'));
    content.append(old);
  }
}

function claimEvent(kind, target) {
  task(async () => {
    const result = await game.claimEvent(kind, target);
    if (result) toast(t('claimResult', {
      n: result.added
    }));
  });
}
let rivalModel;
async function rankingsScreen() {
  screenTitle('ranking', 'rankingInfo');
  if (!rivalModel) {
    const response = await fetch('./data/opponents.json');
    if (!response.ok) throw new Error('Opponent data unavailable');
    rivalModel = new RivalField(await response.json());
  }
  const key = 'sorting-rivals-v1',
    player = game.inspect().player;
  const existing = localStorage.getItem(key);
  let record = existing ? JSON.parse(existing) : rivalModel.create(Date.now(), 480);
  record = rivalModel.advance(record, Date.now(), 480);
  const table = rivalModel.standings(record, {
    id: -1,
    rating: Object.values(player.ratings).reduce((sum, n) => sum + n, 0),
    at: player.ratingAt ?? Date.now()
  });
  localStorage.setItem(key, JSON.stringify(record));
  const self = table.find(row => row.self),
    rows = table.slice(0, 20);
  if (self.rank > 20) rows.push(self);
  content.append(el('p', 'rank-summary', t('yourRank', {
    n: self.rank
  })), standingTable(rows, 'rating'));
}
async function renderCurrent() {
  if (view === 'game' && game.inspect().result && !game.inspect().player.attempt) view = 'result';
  byId('app').dataset.view = view;
  if (view === 'home') home();
  else if (view === 'game') makeGame();
  else if (view === 'result') resultScreen();
  else if (view === 'album') albumScreen();
  else if (view === 'merits') meritsScreen();
  else if (view === 'events') await eventsScreen();
  else if (view === 'ranking') await rankingsScreen();
  header();
}

function changeLocale(next) {
  if (uiBusy) {
    byId('language').value = locale;
    return;
  }
  task(async () => {
    const keepSettings = modal.open && modal.dataset.kind === 'settings';
    locale = next;
    document.documentElement.lang = locale;
    t = translator(locale);
    localStorage.setItem('sorting-language', locale);
    disposeBoard();
    if (keepSettings) openSettings();
    else if (modal.open) modal.close();
  });
}
byId('language').onchange = () => changeLocale(byId('language').value);

function openShop(kind) {
  const frontier = game.inspect().player.frontier;
  if (frontier < 5) return dialog(t('shop'), t('locked', {
    n: 5
  }));
  dialog(t('shop'), t('shopInfo'));
  modal.classList.add('shop-dialog');
  const products = shopProducts(frontier, kind);
  const box = byId('modal-content');
  for (const item of (products.length ? products : shopProducts(frontier))) {
    const offer = productPresentation(item),
      card = el('section', 'product-card'),
      head = el('div', 'product-heading');
    head.append(icon(item.kind === 'energyPack' ? 'heart' : 'sweep'), el('h3', '', t(item.kind)));
    card.append(head);
    const items = el('div', 'product-contents');
    for (const [tool, count] of Object.entries(item.contents)) {
      const row = el('div', 'product-item');
      row.append(icon(tool === 'stamina' ? 'heart' : ['bay', 'tray'].includes(tool) ? 'sweep' : tool), el('span', '', `${t(tool==='stamina'?'powerName':tool)} × ${count}`));
      items.append(row);
    }
    card.append(items);
    const buy = button(offer.displayPrice ?? t('purchaseUnavailable'), () => {}, 'primary');
    buy.disabled = !offer.purchasable;
    card.append(buy);
    box.append(card);
  }
  box.append(el('p', 'settings-note', t('shopOffline')));
}
byId('shop').replaceChildren(icon('sweep'));
byId('shop').onclick = () => openShop();
byId('settings').replaceChildren(icon('gear'));
function openSettings() {
  dialog(t('settings'), t('local'));
  modal.dataset.kind = 'settings';
  const box = byId('modal-content'),
    language = el('select');
  language.setAttribute('aria-label', t('language'));
  for (const [value, name] of [
      ['zh-CN', '简体中文'],
      ['zh-TW', '繁體中文'],
      ['en', 'English']
    ]) {
    const option = el('option', '', name);
    option.value = value;
    language.append(option);
  }
  language.value = locale;
  language.onchange = () => changeLocale(language.value);
  const label = el('label', 'setting-row', t('language'));
  label.append(language);
  box.append(label);
  for (const [key, title, inverted] of [
      ['sorting-sound', 'sound', false],
      ['sorting-motion', 'reduceMotion', true]
    ]) {
    const row = el('label', 'setting-row', t(title)),
      input = el('input');
    input.type = 'checkbox';
    input.checked = inverted ? localStorage.getItem(key) === 'off' : localStorage.getItem(key) !== 'off';
    input.onchange = () => {
      localStorage.setItem(key, (inverted ? !input.checked : input.checked) ? 'on' : 'off');
      document.documentElement.dataset.motion = localStorage.getItem('sorting-motion') ?? 'on';
      if (!motionAllowed()) cleanupFeedback();
      if (view === 'home') home();
    };
    row.append(input);
    box.append(row);
  }
  box.append(el('p', 'settings-note', t(game.inspect().player.attempt && !String(game.inspect().roundEdition).startsWith('neighborhood-') ? 'classicEntry' : 'entry')), el('p', 'settings-note', t('intro')), button(t('lab'), () => task(async () => {
    await game.save();
    location.href = './lab.html';
  })));
}
byId('settings').onclick = openSettings;
byId('lab-link').onclick = event => {
  if (uiBusy) {
    event.preventDefault();
    return;
  }
  event.preventDefault();
  task(async () => {
    await game.save();
    window.location.href = './lab.html';
  });
};
let previous = performance.now(),
  lastSecond = -1,
  sinceSave = 0,
  sinceHeader = 0;

let frameErrorShown = false,
  frameErrors = 0;
// A failing frame must not stop the loop: log it, tell the player once, keep running.
function frame(at) {
  try {
    const elapsed = Math.max(0, Math.min(.25, (at - previous) / 1000));
    previous = at;
    if (game && view === 'game' && !modal.open && !uiBusy && !document.hidden && byId('play-board')?.dataset.graphics !== 'lost' && game.round?.inspect().phase === 'live') {
      const signals = game.advance(elapsed);
      if (signals.length) {
        showSignals(signals);
        board?.draw();
      }
      const second = Math.floor(game.round.inspect().seconds);
      if (second !== lastSecond && byId('play-time')) {
        byId('play-time').textContent = clockText(second);
        lastSecond = second;
      }
      sinceSave += elapsed;
      if (sinceSave >= 5) {
        sinceSave = 0;
        task(() => game.save());
      }
    }
    sinceHeader += elapsed;
    if (game && sinceHeader >= 1 && !uiBusy) {
      sinceHeader = 0;
      const power = game.powerStatus();
      meter('power', 'heart', `${power.amount}/${power.capacity}`, t('energy', {
        n: power.amount,
        max: power.capacity
      }));
      const note = byId('energy-note');
      if (note) note.textContent = `${t('entry')} · ${power.refillIn === null ? t('full') : t('refill', { time: clockText(power.refillIn) })}`;
    }
  } catch (error) {
    // Log the first few only, so a repeating failure does not flood the console every frame.
    if (++frameErrors <= 5) console.error('Frame error', error);
    if (!frameErrorShown) {
      frameErrorShown = true;
      toast(t('frameError'));
    }
  } finally {
    requestAnimationFrame(frame);
  }
}
document.addEventListener('visibilitychange', () => {
  if (document.hidden && game && !uiBusy) task(() => game.save());
  previous = performance.now();
});
window.addEventListener('pagehide', () => {
  // Synchronous final checkpoint; never overwrite a newer save from another tab.
  if (game && !game.busy && localStorage.getItem(SAVE_KEY) === cachedRaw) {
    try {
      const raw = JSON.stringify(game.inspect());
      localStorage.setItem(SAVE_KEY, raw);
      cachedRaw = raw;
    } catch {
      /* Keep the last durable checkpoint. */ }
  }
});
try {
  document.documentElement.dataset.motion = localStorage.getItem('sorting-motion') ?? 'on';
  const boot = record => new Playthrough({
    record,
    // Daily and weekly events follow the player's own time zone (new saves only).
    zone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    loadStage,
    contentEdition: CAMPAIGN_EDITION,
    persist: async snapshot => {
      if (localStorage.getItem(SAVE_KEY) !== cachedRaw) throw new Error('Save changed in another tab. Reload this page.');
      const raw = JSON.stringify(snapshot);
      localStorage.setItem(SAVE_KEY, raw);
      cachedRaw = raw;
    }
  }).initialize();
  const restored = await restoreSavedGame({raw: cachedRaw, key: SAVE_KEY, storage: localStorage, boot});
  game = restored.game;
  const recovered = restored.recovered;
  if (recovered) await game.save();
  document.documentElement.dataset.artEdition='american-v1';

  await renderCurrent();
  if (recovered) toast(t('saveRecovered'));
  requestAnimationFrame(frame);
} catch (error) {
  // The save is untouched here; offer a reload instead of a dead end.
  content.replaceChildren(el('h1', '', t('loadError')), el('p', '', error.message), button(t('reload'), () => location.reload(), 'primary'));
  console.error('Preview initialization failed', error);
}
