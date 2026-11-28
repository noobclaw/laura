const atlas = {
  home: 0,
  album: 1,
  merits: 2,
  events: 3,
  ranking: 4,
  sweep: 5,
  return: 6,
  scan: 7,
  rub: 8
};
const paths = {
  heart: 'M12 20.8C9 18.7 3 14.2 3 8.8 3 3.7 8.8 2.6 12 7c3.2-4.4 9-3.3 9 1.8 0 5.4-6 9.9-9 12Z',
  star: 'M12 2.2 15 8.5l6.8.9-5 4.8 1.3 6.8-6.1-3.4-6.1 3.4 1.3-6.8-5-4.8 6.8-.9Z',
  play: 'M7 4.5q0-1 1-.4l12 7.3q1 .6 0 1.2L8 20q-1 .6-1-.4Z',
  lock: 'M5.5 10h13v10.5h-13Zm3 0V7a3.5 3.5 0 0 1 7 0v3M12 14v3',
  gear: 'M9.5 2.5h5l.8 3 2.3 1.3 3-.8 2.4 4.3-2.2 2.1v2.7l2.2 2.1-2.4 4.3-3-.8-2.3 1.3-.8 3h-5l-.8-3-2.3-1.3-3 .8L1 17.2l2.2-2.1v-2.7L1 10.3 3.4 6l3 .8L8.7 5.5Zm2.5 6.8a3.7 3.7 0 1 0 0 7.4 3.7 3.7 0 0 0 0-7.4',
  map: 'M3 5.5 8.5 3 15.5 5.5 21 3v15.5L15.5 21l-7-2.5L3 21Zm5.5-2.5v15.5m7-13v15.5',
  pause: 'M6.5 4h3v16h-3Zm8 0h3v16h-3Z',
  back: 'M15.5 5 8 12l7.5 7M8 12h12',
  close: 'M6 6 18 18M18 6 6 18',
  sound: 'M4 9h3.5L13 5v14l-5.5-4H4Zm12-.8q3.5 3.8 0 7.6m3-10.2q5.8 6.4 0 12.8',
};
export function icon(name) {
  if (name in atlas) {
    const node = document.createElement('span'),
      index = atlas[name];
    node.className = 'game-icon';
    node.dataset.icon = name;
    node.style.backgroundPosition = `${index%3*50}% ${Math.floor(index/3)*50}%`;
    node.setAttribute('aria-hidden', 'true');
    return node;
  }
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.classList.add('glyph', `glyph-${name}`);
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(svg.namespaceURI, 'path');
  path.setAttribute('d', paths[name] ?? paths.star);
  if (['back', 'close', 'map', 'sound', 'lock'].includes(name)) {
    path.setAttribute('fill', 'none');
    path.setAttribute('stroke', 'currentColor');
    path.setAttribute('stroke-width', '2.5');
    path.setAttribute('stroke-linecap', 'round');
    path.setAttribute('stroke-linejoin', 'round');
  } else path.setAttribute('fill', 'currentColor');
  svg.append(path);
  return svg;
}
