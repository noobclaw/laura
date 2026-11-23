# Asset log — Lantern prototype

Every third-party file used by the prototype is listed here. Add a row before adding a file.

| File | Source pack | Original file | Author | License | Changes |
|---|---|---|---|---|---|
| fx/star_06.png, star_07.png, star_09.png, circle_02.png, circle_05.png, magic_05.png, symbol_02.png | Particle Pack 1.1 | PNG (Transparent)/ same names | Kenney Vleugels (kenney.nl) | CC0 1.0 | Resized 512 to 128 px, tinted at runtime |
| sfx/place | Interface Sounds | pluck_002.ogg | Kenney (kenney.nl) | CC0 1.0 | Added MP3 copy, pitch shifted at runtime |
| sfx/mark | Interface Sounds | tick_001.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/tap | Interface Sounds | click_001.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/bad | Interface Sounds | error_004.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/lift | Interface Sounds | drop_002.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/hint | Interface Sounds | glass_001.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/rise | Interface Sounds | confirmation_002.ogg | Kenney | CC0 1.0 | Added MP3 copy |
| sfx/win | Music Jingles | Pizzicato jingles/jingles_PIZZI07.ogg | Kenney | CC0 1.0 | Added MP3 copy |

Files were taken from the third-party mirror github.com/ETdoFresh/kenney.nl; each pack ships a License.txt stating CC0.
CC0 needs no credit. Lanterns, tiles, backgrounds and UI are drawn in code and are our own work.
The font Baloo Bhaijaan 2 is loaded from Google Fonts (SIL Open Font License); bundle it for release builds.

| ../vendor/three.min.js | three.js r188dev (github.com/mrdoob/three.js, commit 57c4530) | build/three.module.js | Three.js Authors | MIT (vendor/THREE-LICENSE.txt) | Bundled and minified into one script with esbuild |
