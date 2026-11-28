import {
  readStage
} from './catalog.js';
import { normalizeCategories } from './categories.js';

export const CAMPAIGN_EDITION = 'neighborhood-3';
export const isNeighborhood = edition => ['neighborhood-1', 'neighborhood-2', CAMPAIGN_EDITION].includes(edition);
export const TOOL_UNLOCKS = Object.freeze({
  scan: 3,
  return: 4,
  sweep: 5,
  rub: 7
});
const openingCounts = [18, 28, 36, 44, 52, 60, 66, 72, 64, 84, 76, 90, 98, 84, 108, 116, 104, 128, 144, 164];
export function toolUnlock(kind, edition = CAMPAIGN_EDITION) {
  return isNeighborhood(edition) ? TOOL_UNLOCKS[kind] ?? 1 : 3;
}
export function campaignProfile(number) {
  if (!Number.isInteger(number) || number < 1 || number > 160) throw new RangeError('Unknown campaign stage');
  return {
    number,
    target: openingCounts[number - 1] ?? null,
    pace: [9, 11, 14, 17].includes(number) ? 'breather' : [10, 15, 20].includes(number) ? 'challenge' : number <= 5 ? 'learning' : 'normal'
  };
}
export function balanceStage(payload, number, edition = CAMPAIGN_EDITION) {
  if (edition === CAMPAIGN_EDITION) payload = normalizeCategories(payload);
  const profile = campaignProfile(number);
  if (profile.target === null) return {
    ...payload,
    campaign: {
      edition,
      ...profile
    }
  };
  const available = new Map();
  payload.stage.specimens.forEach((token, id) => {
    if (!available.has(token.group)) available.set(token.group, []);
    available.get(token.group).push(id);
  });
  const order = [...new Set(payload.stage.shipments.map(request => request.group))];
  const target = Math.min(profile.target, payload.stage.specimens.length),
    chosen = [];
  let cap = edition === 'neighborhood-1' ? Infinity : 6;
  while (order.reduce((sum, group) => sum + Math.min(cap, available.get(group)?.length ?? 0), 0) < target) cap++;
  let capacity = 0;
  for (const group of order) {
    chosen.push(group);
    capacity += Math.min(cap, available.get(group)?.length ?? 0);
    if (capacity >= target && chosen.length >= Math.min(4, order.length)) break;
  }
  const quota = new Map(chosen.map(group => [group, 0]));
  for (let count = 0; count < target;) {
    for (const group of chosen) {
      if (count === target) break;
      if (quota.get(group) < Math.min(cap, available.get(group).length)) {
        quota.set(group, quota.get(group) + 1);
        count++;
      }
    }
  }
  const selected = [];
  for (const group of chosen) {
    const ids = available.get(group).slice(-quota.get(group));
    for (const id of ids) selected.push({
      id,
      group,
      wave: Math.floor(chosen.indexOf(group) / 2)
    });
  }
  // Each two-category wave sits above later waves. Both active requests have a reachable route.
  selected.sort((a, b) => b.wave - a.wave || a.id - b.id);
  const specimens = selected.map(({
    id
  }) => structuredClone(payload.stage.specimens[id]));
  const forms = Object.fromEntries([...new Set(specimens.map(token => token.form))].map(key => [key, payload.forms[key]]));
  const sprites = Object.fromEntries(Object.keys(forms).map(key => [key, payload.scene.sprites[key]]));
  const fast = Math.max(60, Math.ceil(target * 3.5)),
    medium = Math.max(100, Math.ceil(target * 5.5));
  return {
    stage: {
      ...payload.stage,
      specimens,
      shipments: chosen.filter(group => quota.get(group) > 0).map(group => ({
        group,
        quantity: quota.get(group)
      })),
      rating: {
        fast,
        medium
      }
    },
    forms,
    scene: {
      ...payload.scene,
      sprites
    },
    campaign: {
      edition,
      ...profile,
      quantity: target
    }
  };
}
export async function readCampaignStage(number, {
  edition = CAMPAIGN_EDITION
} = {}) {
  const payload = await readStage(number);
  return isNeighborhood(edition) ? balanceStage(payload, number, edition) : payload;
}
