// Copies data/rules.json into data/rules.js so the game still opens from file:// (Chrome blocks fetch of local JSON).
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'data');
const json = JSON.parse(fs.readFileSync(path.join(dir, 'rules.json'), 'utf8'));
fs.writeFileSync(path.join(dir, 'rules.js'), '/* GENERATED from rules.json by tools/build-rules.js — do not edit */\nwindow.SG_RULES = ' + JSON.stringify(json, null, 1) + ';\n');
console.log('rules.js written');
