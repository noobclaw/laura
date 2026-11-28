const TOLERANCE = 0.0001;
const footprints = new WeakMap();
const decoded = new WeakMap();
const orient = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
const closeTo = (a, b) => Math.abs(a[0] - b[0]) <= TOLERANCE && Math.abs(a[1] - b[1]) <= TOLERANCE;

export function windingArea(vertices) {
  return vertices.reduce((sum, p, i) => {
    const q = vertices[(i + 1) % vertices.length];
    return sum + p[0] * q[1] - q[0] * p[1];
  }, 0) / 2;
}
export const polygonArea = vertices => Math.abs(windingArea(vertices));

export function envelope(vertices) {
  const box = {
    left: Infinity,
    right: -Infinity,
    bottom: Infinity,
    top: -Infinity
  };
  for (const [u, v] of vertices) {
    box.left = Math.min(box.left, u);
    box.right = Math.max(box.right, u);
    box.bottom = Math.min(box.bottom, v);
    box.top = Math.max(box.top, v);
  }
  return box;
}
export const boxesMeet = (a, b) => !(a.left > b.right || a.right < b.left || a.bottom > b.top || a.top < b.bottom);

export function moveVertices(vertices, pose) {
  const radians = pose.heading * Math.PI / 180;
  const cosine = Math.cos(radians),
    sine = Math.sin(radians);
  return vertices.map(([u, v]) => {
    u *= pose.stretch[0];
    v *= pose.stretch[1];
    return [u * cosine - v * sine + pose.at[0], u * sine + v * cosine + pose.at[1]];
  });
}
export function rectangularEnvelope(extent, pose) {
  const [w, h] = extent;
  return envelope(moveVertices([
    [-w / 2, -h / 2],
    [w / 2, -h / 2],
    [w / 2, h / 2],
    [-w / 2, h / 2]
  ], pose));
}

function readRaster(grid) {
  if (decoded.has(grid)) return decoded.get(grid);
  const {
    columns,
    rows,
    bits
  } = grid;
  if (!Number.isInteger(columns) || !Number.isInteger(rows) || columns <= 0 || rows <= 0 || columns * rows > 1000000) throw new TypeError('Invalid contour raster');
  let bytes;
  try {
    bytes = Uint8Array.from(atob(bits), c => c.charCodeAt(0));
  } catch {
    throw new TypeError('Invalid contour raster');
  }
  if (bytes.length !== Math.ceil(columns * rows / 8)) throw new TypeError('Invalid contour raster');
  const filled = [],
    strips = [];
  for (let row = 0; row < rows; row++) {
    let begin = -1;
    for (let col = 0; col <= columns; col++) {
      const bit = row * columns + col;
      const solid = col < columns && (bytes[bit >>> 3] & (1 << (bit & 7))) !== 0;
      if (solid) {
        filled.push(bit);
        if (begin < 0) begin = col;
      } else if (begin >= 0) {
        strips.push(begin, col, row);
        begin = -1;
      }
    }
  }
  const result = {
    columns,
    rows,
    bytes,
    filled: Uint32Array.from(filled),
    strips: Uint32Array.from(strips)
  };
  decoded.set(grid, result);
  return result;
}

export function composeOutline(definition, pose) {
  const contour = moveVertices(definition.outline, pose);
  if (!definition.grid) return contour;
  const [w, h] = definition.extent;
  if (![w, h].every(n => Number.isFinite(n) && n > 0) || ![...pose.at, ...pose.stretch, pose.heading].every(Number.isFinite) || pose.stretch.includes(0)) throw new TypeError('Invalid contour transform');
  const raster = readRaster(definition.grid),
    angle = pose.heading * Math.PI / 180;
  const c = Math.cos(angle),
    s = Math.sin(angle),
    width = w * pose.stretch[0],
    height = h * pose.stretch[1];
  const centers = new Float64Array(raster.filled.length * 2);
  for (let i = 0; i < raster.filled.length; i++) {
    const col = raster.filled[i] % raster.columns,
      row = Math.floor(raster.filled[i] / raster.columns);
    const u = ((col + .5) / raster.columns - .5) * width,
      v = (.5 - (row + .5) / raster.rows) * height;
    centers[i * 2] = u * c - v * s + pose.at[0];
    centers[i * 2 + 1] = u * s + v * c + pose.at[1];
  }
  footprints.set(contour, {
    raster,
    c,
    s,
    width,
    height,
    origin: pose.at,
    centers,
    coverCache: new WeakMap()
  });
  return contour;
}

function rasterHit(point, info) {
  const u = point[0] - info.origin[0],
    v = point[1] - info.origin[1];
  const col = Math.floor(((u * info.c + v * info.s) / info.width + .5) * info.raster.columns);
  const row = Math.floor((.5 - (-u * info.s + v * info.c) / info.height) * info.raster.rows);
  if (col < 0 || row < 0 || col >= info.raster.columns || row >= info.raster.rows) return false;
  const bit = row * info.raster.columns + col;
  return (info.raster.bytes[bit >>> 3] & (1 << (bit & 7))) !== 0;
}

function alongEdge(point, a, b) {
  return Math.abs(orient(a, b, point)) <= TOLERANCE &&
    point[0] >= Math.min(a[0], b[0]) - TOLERANCE && point[0] <= Math.max(a[0], b[0]) + TOLERANCE &&
    point[1] >= Math.min(a[1], b[1]) - TOLERANCE && point[1] <= Math.max(a[1], b[1]) + TOLERANCE;
}
export function containsPoint(point, vertices) {
  const info = footprints.get(vertices);
  if (info) return rasterHit(point, info);
  let crossings = 0;
  for (let edge = 0; edge < vertices.length; edge++) {
    const a = vertices[edge],
      b = vertices[(edge + 1) % vertices.length];
    if (alongEdge(point, a, b)) return true;
    if ((a[1] > point[1]) !== (b[1] > point[1]) && point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0]) crossings++;
  }
  return crossings % 2 === 1;
}
export function distanceFromContour(point, vertices) {
  if (containsPoint(point, vertices)) return 0;
  const info = footprints.get(vertices);
  if (info) {
    const du = point[0] - info.origin[0],
      dv = point[1] - info.origin[1];
    const u = (du * info.c + dv * info.s) * Math.sign(info.width),
      v = (-du * info.s + dv * info.c) * Math.sign(info.height);
    const width = Math.abs(info.width),
      height = Math.abs(info.height);
    let nearest = Infinity;
    for (let i = 0; i < info.raster.strips.length; i += 3) {
      const [begin, end, row] = info.raster.strips.subarray(i, i + 3);
      const left = (begin / info.raster.columns - .5) * width,
        right = (end / info.raster.columns - .5) * width;
      const top = (.5 - row / info.raster.rows) * height,
        bottom = top - height / info.raster.rows;
      nearest = Math.min(nearest, Math.hypot(Math.max(left - u, 0, u - right), Math.max(bottom - v, 0, v - top)));
    }
    return nearest;
  }
  let nearest = Infinity;
  for (let i = 0; i < vertices.length; i++) {
    const a = vertices[i],
      b = vertices[(i + 1) % vertices.length],
      u = b[0] - a[0],
      v = b[1] - a[1];
    const length = u * u + v * v,
      projection = length ? Math.max(0, Math.min(1, ((point[0] - a[0]) * u + (point[1] - a[1]) * v) / length)) : 0;
    nearest = Math.min(nearest, Math.hypot(point[0] - a[0] - projection * u, point[1] - a[1] - projection * v));
  }
  return nearest;
}

function edgesMeet(a, b, c, d) {
  const values = [orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)];
  if (((values[0] > TOLERANCE && values[1] < -TOLERANCE) || (values[0] < -TOLERANCE && values[1] > TOLERANCE)) &&
    ((values[2] > TOLERANCE && values[3] < -TOLERANCE) || (values[2] < -TOLERANCE && values[3] > TOLERANCE))) return true;
  return (Math.abs(values[0]) <= TOLERANCE && alongEdge(c, a, b)) || (Math.abs(values[1]) <= TOLERANCE && alongEdge(d, a, b)) ||
    (Math.abs(values[2]) <= TOLERANCE && alongEdge(a, c, d)) || (Math.abs(values[3]) <= TOLERANCE && alongEdge(b, c, d));
}
export function contoursMeet(first, second) {
  if (footprints.has(first) || footprints.has(second)) return boxesMeet(envelope(first), envelope(second));
  for (let a = 0; a < first.length; a++)
    for (let b = 0; b < second.length; b++)
      if (edgesMeet(first[a], first[(a + 1) % first.length], second[b], second[(b + 1) % second.length])) return true;
  return containsPoint(first[0], second) || containsPoint(second[0], first);
}

function tidy(vertices) {
  const result = [];
  for (const point of vertices)
    if (!result.length || !closeTo(result.at(-1), point)) result.push(point);
  if (result.length > 1 && closeTo(result[0], result.at(-1))) result.pop();
  let removed = true;
  while (removed && result.length > 3) {
    removed = false;
    for (let i = 0; i < result.length; i++) {
      const before = result[(i + result.length - 1) % result.length],
        after = result[(i + 1) % result.length];
      if (closeTo(before, result[i]) || closeTo(after, result[i]) || alongEdge(result[i], before, after)) {
        result.splice(i, 1);
        removed = true;
        break;
      }
    }
  }
  return result.length < 3 ? [] : result;
}

function insideTriangle(p, a, b, c) {
  const turns = [orient(a, b, p), orient(b, c, p), orient(c, a, p)];
  return !(turns.some(n => n < -TOLERANCE) && turns.some(n => n > TOLERANCE));
}
export function decompose(vertices) {
  const remaining = tidy(vertices);
  if (remaining.length < 3) return [];
  if (remaining.length === 3) return [remaining];
  const sign = Math.sign(windingArea(remaining));
  if (polygonArea(remaining) <= TOLERANCE) return [];
  const triangles = [];
  while (remaining.length > 3) {
    let found = false;
    for (let middle = 0; middle < remaining.length; middle++) {
      const left = (middle + remaining.length - 1) % remaining.length,
        right = (middle + 1) % remaining.length;
      const a = remaining[left],
        b = remaining[middle],
        c = remaining[right];
      if (sign * orient(a, b, c) <= TOLERANCE) continue;
      if (remaining.some((p, i) => i !== left && i !== middle && i !== right && insideTriangle(p, a, b, c))) continue;
      triangles.push([a, b, c]);
      remaining.splice(middle, 1);
      found = true;
      break;
    }
    if (!found) return [];
  }
  triangles.push(remaining);
  return triangles;
}

function crossing(sourceStart, sourceEnd, edgeStart, edgeEnd) {
  const direction = sourceEnd.map((coordinate, i) => coordinate - sourceStart[i]);
  const boundary = edgeEnd.map((coordinate, i) => coordinate - edgeStart[i]);
  const displacement = edgeStart.map((coordinate, i) => coordinate - sourceStart[i]);
  const determinant = (u, v) => u[0] * v[1] - u[1] * v[0];
  const divisor = determinant(direction, boundary);
  if (Math.abs(divisor) <= TOLERANCE) return [...sourceEnd];
  const fraction = determinant(displacement, boundary) / divisor;
  return sourceStart.map((coordinate, i) => coordinate + fraction * direction[i]);
}

function cutConvex(vertices, boundary) {
  let pieces = vertices.slice();
  const direction = Math.sign(windingArea(boundary));
  if (!direction) return [];
  for (let edge = 0; edge < boundary.length && pieces.length; edge++) {
    const a = boundary[edge],
      b = boundary[(edge + 1) % boundary.length],
      input = pieces;
    pieces = [];
    let last = input.at(-1),
      lastInside = direction * orient(a, b, last) >= -TOLERANCE;
    for (const point of input) {
      const currentInside = direction * orient(a, b, point) >= -TOLERANCE;
      if (currentInside !== lastInside) pieces.push(crossing(last, point, a, b));
      if (currentInside) pieces.push(point);
      last = point;
      lastInside = currentInside;
    }
  }
  return pieces;
}
export function sharedArea(contours) {
  if (contours.some(p => footprints.has(p))) return null;
  const groups = contours.map(tidy).filter(p => p.length >= 3).map(decompose);
  if (!groups.length || groups.some(p => !p.length)) return null;
  let fragments = groups[0];
  for (const triangles of groups.slice(1)) {
    const next = [];
    for (const fragment of fragments)
      for (const triangle of triangles) {
        const cut = tidy(cutConvex(fragment, triangle));
        if (cut.length >= 3) next.push(cut);
      }
    fragments = next;
    if (!fragments.length) return 0;
  }
  return fragments.reduce((sum, p) => sum + polygonArea(p), 0);
}
export function sampledCoverage(target, blockers, resolution = 64) {
  const box = envelope(target),
    width = box.right - box.left,
    height = box.top - box.bottom;
  if (target.length < 3 || !blockers.length || polygonArea(target) <= TOLERANCE || width <= TOLERANCE || height <= TOLERANCE) return 0;
  const count = Math.max(8, Math.floor(resolution));
  let accepted = 0,
    obstructed = 0;
  for (let col = 0; col < count; col++)
    for (let row = 0; row < count; row++) {
      const point = [box.left + (col + .5) * width / count, box.bottom + (row + .5) * height / count];
      if (containsPoint(point, target)) {
        accepted++;
        if (blockers.some(p => containsPoint(point, p))) obstructed++;
      }
    }
  return accepted ? obstructed / accepted : 0;
}

function rasterCoverage(target, blockers) {
  const info = footprints.get(target);
  if (!info.centers.length) return 0;
  const marked = new Uint8Array(info.centers.length / 2);
  for (const blocker of blockers) {
    let bitmap = info.coverCache.get(blocker);
    if (!bitmap) {
      bitmap = new Uint8Array(marked.length);
      for (let i = 0; i < bitmap.length; i++) bitmap[i] = Number(containsPoint([info.centers[i * 2], info.centers[i * 2 + 1]], blocker));
      info.coverCache.set(blocker, bitmap);
    }
    for (let i = 0; i < bitmap.length; i++) marked[i] |= bitmap[i];
  }
  return marked.reduce((sum, n) => sum + n, 0) / marked.length;
}
export function coverageFraction(target, blockers, exactMaximum = 2) {
  if (!blockers.length) return 0;
  if (footprints.has(target)) return rasterCoverage(target, blockers);
  if (blockers.some(p => footprints.has(p))) return sampledCoverage(target, blockers);
  const whole = polygonArea(target);
  if (whole <= TOLERANCE) return 0;
  if (blockers.length <= exactMaximum) {
    let covered = 0;
    for (let selection = 1; selection < 2 ** blockers.length; selection++) {
      const group = [target];
      let members = 0;
      blockers.forEach((p, i) => {
        if (selection & (1 << i)) {
          group.push(p);
          members++;
        }
      });
      const overlap = sharedArea(group);
      if (overlap === null) return sampledCoverage(target, blockers);
      covered += (members % 2 ? 1 : -1) * overlap;
    }
    return Math.max(0, Math.min(1, Math.max(0, covered) / whole));
  }
  return sampledCoverage(target, blockers);
}
