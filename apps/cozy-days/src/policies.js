export const ROUND_LIMITS = Object.freeze({
  requestPlaces: 3,
  initialRequests: 2,
  trayPlaces: 7,
  initialTrayPlaces: 5,
  contactFraction: 0.01,
  obstructionFraction: 0.045,
  exactOccluders: 2,
  idleSeconds: 15,
  idlePrompts: 3,
  returnBatch: 3,
  scanCapacity: 5,
});

export const ACCOUNT_LIMITS = Object.freeze({
  staminaLimit: 5,
  entryCharge: 1,
  refillSeconds: 1800,
  videoRefill: 1,
  victoryRefill: 0,
  fastSecondsPerToken: 3,
  mediumSecondsPerToken: 5,
  rewardStaminaLimit: 30,
  assistStage: 3,
});

const TRAY_MODES = Object.freeze({
  flexible: {
    available: 5,
    places: 7,
    immediateLoss: false,
    notice: false
  },
  explanatory: {
    available: 5,
    places: 7,
    immediateLoss: false,
    notice: true
  },
  strict: {
    available: 5,
    places: 7,
    immediateLoss: true,
    notice: false
  },
  expanded: {
    available: 6,
    places: 8,
    immediateLoss: true,
    notice: false
  },
});

export function traySettings(mode = 'flexible') {
  if (!Object.hasOwn(TRAY_MODES, mode)) throw new RangeError('Unknown tray policy');
  return {
    ...TRAY_MODES[mode]
  };
}

export function validateGrouping(grouping) {
  if (!grouping || !Array.isArray(grouping.pairs) || grouping.pairs.length < 1 || grouping.pairs.length > 512) return false;
  const sourceIds = new Set();
  for (const pair of grouping.pairs) {
    if (!Array.isArray(pair) || pair.length !== 2 || pair.some(v => !Number.isSafeInteger(v) || v <= 0)) return false;
    if (pair[0] === pair[1] || sourceIds.has(pair[0])) return false;
    sourceIds.add(pair[0]);
  }
  return grouping.pairs.every(([, destination]) => !sourceIds.has(destination));
}

export function ratingFor(seconds, quantity, settings = ACCOUNT_LIMITS, timing = 'scaled') {
  if (timing && typeof timing === 'object') {
    if (!Number.isFinite(timing.fast) || !Number.isFinite(timing.medium) || timing.fast < 0 || timing.medium < timing.fast) throw new TypeError('Invalid star timing');
    return seconds <= timing.fast ? 3 : seconds <= timing.medium ? 2 : 1;
  }
  const thresholds = timing === 'fixed' ? [720, 960] : [quantity * settings.fastSecondsPerToken, quantity * settings.mediumSecondsPerToken];
  return seconds <= thresholds[0] ? 3 : seconds <= thresholds[1] ? 2 : 1;
}
