import {
  rectangularEnvelope
} from './spatial.js';
import { resolvePose } from './poses.js';
export function frameFor(payload) {
  if (payload.scene.worldFrame) return structuredClone(payload.scene.worldFrame);
  const boxes = payload.stage.specimens.map((token,id) => rectangularEnvelope(payload.forms[token.form].extent, resolvePose(token,payload.forms[token.form],id)));
  if (!boxes.length) return {
    center: [0, 0],
    extent: [...payload.scene.extent]
  };
  const left = Math.min(...boxes.map(b => b.left)),
    right = Math.max(...boxes.map(b => b.right)),
    bottom = Math.min(...boxes.map(b => b.bottom)),
    top = Math.max(...boxes.map(b => b.top));
  return {
    center: [(left + right) / 2, (bottom + top) / 2],
    extent: [Math.max(payload.scene.extent[0] * .65, right - left + 80), Math.max(payload.scene.extent[1] * .60, top - bottom + 80)]
  };
}
export function viewTransform(frame, width, height, magnification = 1, pan = [0, 0]) {
  const zoom = Math.min(width / frame.extent[0], height / frame.extent[1]) * magnification;
  const limits = [Math.max(0, (frame.extent[0] - width / zoom) / 2), Math.max(0, (frame.extent[1] - height / zoom) / 2)];
  const center = frame.center.map((value, i) => value + Math.max(-limits[i], Math.min(limits[i], pan[i])));
  return {
    zoom,
    center
  };
}
export const worldToScreen = (point, view, width, height) => [width / 2 + (point[0] - view.center[0]) * view.zoom, height / 2 - (point[1] - view.center[1]) * view.zoom];
export const screenToWorld = (point, view, width, height) => [(point[0] - width / 2) / view.zoom + view.center[0], -(point[1] - height / 2) / view.zoom + view.center[1]];
