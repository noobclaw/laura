/* GENERATED from rules.json by tools/build-rules.js — do not edit */
window.SG_RULES = {
 "_comment": "All tuning numbers come from design/gdd/*.md. Edit here, then run: node tools/build-rules.js",
 "round": {
  "prepSec": 60,
  "seekSec": 300,
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
  "walkSpeed": 2.4,
  "crouchSpeed": 1,
  "jumpHeight": 1.1,
  "jumpHeightShortLeg": 0.8,
  "clingSpeed": 1.6,
  "stillSpeed": 0.05,
  "meowRange": 12,
  "maxDecoys": 2,
  "decoyCooldownSec": 30,
  "bumpRadius": 0.28,
  "forcedMeowSec": 45,
  "forcedMeowMinSec": 5,
  "embedRatio": 0.6,
  "embedSec": 3,
  "runSpeed": 5,
  "sizes": [
   1,
   1.4,
   1.7
  ],
  "accel": 16,
  "decel": 10,
  "posedSpeed": 0.8,
  "nudgeSpeed": 0.15
 },
 "dog": {
  "speed": 2.6,
  "startAmmo": 5,
  "shotIntervalSec": 1.5,
  "missDelta": -1,
  "hitDelta": 1,
  "fleeingSpeed": 1,
  "pelletSpeed": 60,
  "pelletGravity": 2.5,
  "range": 25,
  "lowAmmoWarn": 1,
  "eyeHeightDefault": 0.2,
  "eyeHeightRear": 0.47,
  "crouchEye": 0.55,
  "crouchSpeed": 0.5,
  "jumpHeight": 0.55,
  "pellets": 7,
  "spreadRad": 0.035,
  "eyeHeight": {
   "shiba": 0.62,
   "corgi": 0.4,
   "bull": 0.5,
   "poodle": 0.86,
   "dachs": 0.36,
   "husky": 0.72
  },
  "runSpeed": 5.4,
  "bodyRad": 0.18
 },
 "overlooked": {
  "tickEverySec": 0.5,
  "minArea": 0.00004,
  "maxPerTick": 45,
  "deadZone": 0.1,
  "edgeFactor": 0.15,
  "nearM": 5,
  "farM": 22,
  "farFactor": 0.25,
  "boardEverySec": 30,
  "streakGapSec": 1.2
 },
 "move": {
  "stepUp": 0.24
 },
 "paint": {
  "textureSize": 1024,
  "brushMinCm": 1,
  "brushMaxCm": 20,
  "brushDefaultCm": 7,
  "opacity": 1,
  "hardnessHard": 0.85,
  "hardnessSoft": 0.3,
  "undoSteps": 24,
  "suggestDistance": 0.6
 },
 "solo": {
  "_comment": "defaults when playing alone with bots (ours); multiplayer keeps round.*",
  "prepSec": 60,
  "seekSec": 300,
  "mode": "infection",
  "botCatsWhenCat": 9,
  "botDogsWhenCat": 1,
  "botCatsWhenDog": 10,
  "botDogsWhenDog": 1
 },
 "feel": {
  "_comment": "feedback only, no points (ours)",
  "nearMissDogM": 1.3,
  "nearMissPelletM": 0.6,
  "stareSecMin": 1,
  "stareSecMax": 3,
  "fidgetMinSec": 9,
  "fidgetMaxSec": 26
 },
 "bot": {
  "dogViewDistance": 7,
  "dogFovDeg": 70,
  "dogSuspicionGain": 2.6,
  "dogSuspicionDecay": 0.35,
  "dogMismatchFloor": 0.045,
  "catMoveSuspicion": 3,
  "patrolSpeed": 2.8,
  "relocateEverySec": [
   35,
   70
  ]
 },
 "lobby": {
  "lotterySec": 20
 }
};
