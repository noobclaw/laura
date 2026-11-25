/* GENERATED from rules.json by tools/build-rules.js — do not edit */
window.SG_RULES = {
 "_comment": "All tuning numbers come from design/gdd/*.md. Edit here, then run: node tools/build-rules.js",
 "round": {
  "prepSec": 120,
  "seekSec": 180,
  "revealSec": 30,
  "minPlayers": 2
 },
 "dogCount": [
  {
   "maxPlayers": 5,
   "dogs": 1
  },
  {
   "maxPlayers": 9,
   "dogs": 2
  },
  {
   "maxPlayers": 14,
   "dogs": 3
  }
 ],
 "cat": {
  "walkSpeed": 2.2,
  "crouchSpeed": 0.9,
  "jumpHeight": 1.1,
  "jumpHeightShortLeg": 0.8,
  "clingSpeed": 1,
  "stillSpeed": 0.05,
  "meowRange": 12,
  "maxDecoys": 2,
  "decoyCooldownSec": 30,
  "bumpRadius": 0.28,
  "forcedMeowSec": 45,
  "forcedMeowMinSec": 5,
  "embedRatio": 0.6,
  "embedSec": 3
 },
 "dog": {
  "speed": 3,
  "startBalls": 5,
  "shotIntervalSec": 1.5,
  "missDelta": -1,
  "hitDelta": 1,
  "fleeingSpeed": 1,
  "ballSpeed": 40,
  "ballGravity": 2.5,
  "ballRange": 25,
  "lowBallWarn": 1,
  "eyeHeight": {
   "shiba": 0.62,
   "corgi": 0.4,
   "bull": 0.5,
   "poodle": 0.86,
   "dachs": 0.36,
   "husky": 0.72
  }
 },
 "overlooked": {
  "checkEverySec": 0.5,
  "minArea": 0.0005,
  "coef": 10,
  "boardEverySec": 30
 },
 "paint": {
  "textureSize": 1024,
  "brushMinCm": 1,
  "brushMaxCm": 20,
  "brushDefaultCm": 6,
  "hardnessHard": 0.85,
  "hardnessSoft": 0.3,
  "undoSteps": 24,
  "suggestDistance": 0.6
 },
 "bot": {
  "dogViewDistance": 7,
  "dogFovDeg": 70,
  "dogSuspicionGain": 2.6,
  "dogSuspicionDecay": 0.35,
  "dogMismatchFloor": 0.045,
  "catMoveSuspicion": 3
 }
};
