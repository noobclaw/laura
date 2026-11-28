import manifest from '../presentation/american-v1/manifest.json' with { type: 'json' };
import { frameFor } from './view.js';
import { rectangularEnvelope } from './spatial.js';
import { requestLabel } from './requests.js';

export const ART_EDITION = 'american-v1';
export const newArt = manifest;

function roomFor(payload) {
  const opening=['porch','laundry','garage','playroom','kitchen','studio','garden','market'];
  if (payload.stage.number<=opening.length) return opening[payload.stage.number-1];
  const names=payload.stage.shipments.map(x=>requestLabel(x.group,'en')).join(' ').toLowerCase();
  const choose = [
    ['studio',/computer|pc accessories|stationery|notebook|textbook|paint|pottery|sewing|vinyl|record|audio|folder|pencil|desk|printer/],
    ['garden',/garden|flower|plant|potting|seed|pumpkin|hose|watering/],
    ['kitchen',/food|bread|milk|fruit|vegg|cooking|sauce|cheese|apple|coffee|cake|cup|kitchen|cutlery|pizza|sandwich|egg|baking/],
    ['garage',/tool|car |wiper|engine|tire|sports|baseball|bowling|scooter|helmet|drill/],
    ['playroom',/toy|game|plush|doll|bear|rabbit|dinosaur|frog|unicorn|penguin|block|puzzle/],
    ['market',/price|bank|money|order|parcel|packaging|paper bag/],
    ['laundry',/laundry|towel|glove|sock|cloth|pant|shirt|skirt|hanger|shampoo|soap|mask/],
  ].find(([,pattern])=>pattern.test(names));
  return choose?.[0]??'porch';
}

// Presentation replacement leaves stage identity and every persisted token index
// intact. New silhouettes receive readable extents and shared display poses.
export function applyAmericanArt(payload) {
  if (!manifest.complete) throw new Error('Original art production is incomplete');
  const frame=frameFor(payload), forms={}, sprites={}, roles=new Map();
  const accessoryForms=[...new Set(payload.stage.specimens.filter(token=>/PC Accessories|Computer accessories/.test(requestLabel(token.group,'en'))).map(token=>token.form))].sort();
  const accessoryKeys=['PC Accessories','computer mouse','over ear headphones'].map(name=>Object.keys(manifest.items).find(key=>manifest.items[key].category===name));
  const keyboardForm=accessoryForms.reduce((best,key)=>!best||payload.forms[key].extent[0]/payload.forms[key].extent[1]>payload.forms[best].extent[0]/payload.forms[best].extent[1]?key:best,null);
  const sportsKeys=['Sports Gear','baseball glove','baseball','American football'].map(name=>Object.keys(manifest.items).find(key=>manifest.items[key].category===name));
  const sportsForms=[...new Set(payload.stage.specimens.filter(token=>requestLabel(token.group,'en')==='Sports Gear').map(token=>token.form))].sort();
  for (const token of payload.stage.specimens) {
    const index=accessoryForms.indexOf(token.form);
    const aspect=payload.forms[token.form].extent[0]/payload.forms[token.form].extent[1];
    const sport=sportsForms.indexOf(token.form);
    const key=index>=0?accessoryKeys[token.form===keyboardForm||aspect>1.65?0:index%2?1:2]:sport>=0?sportsKeys[sport%sportsKeys.length]:manifest.groups[token.group];
    if (!key || !manifest.items[key]) throw new Error(`Missing new category art ${token.group}`);
    if (!roles.has(token.form)) roles.set(token.form,key);
    else if (roles.get(token.form)!==key) throw new Error(`Ambiguous new form ${token.form}`);
  }
  for (const [form,key] of roles) {
    const art=manifest.items[key], old=payload.forms[form];
    const fit=Math.min(old.extent[0]/art.pixels[0],old.extent[1]/art.pixels[1]);
    const extent=art.pixels.map(x=>x*fit);
    const scales=payload.stage.specimens.filter(token=>token.form===form).map(token=>Math.max(...token.stretch.map(Math.abs))).sort((a,b)=>a-b);
    const naturalZoom=Math.min(368/frame.extent[0],600/frame.extent[1]);
    const nativeSize=Math.max(...extent)*scales[scales.length-1]*naturalZoom;
    const factor=Math.min(6,(payload.stage.number<=6?52:46)/Math.max(1,nativeSize));
    extent[0]*=factor;extent[1]*=factor;
    forms[form]={extent,grid:art.grid,outline:art.outline.map(([x,y])=>[x*extent[0],y*extent[1]]),locations:{}};
    sprites[form]=art.path;
  }
  // New art needs readable native dimensions. Keep the raw stage records intact,
  // enlarge its matching collision shape, and only expand the camera envelope
  // when required to keep a newly larger edge visible.
  const originalBoxes=payload.stage.specimens.map(token=>rectangularEnvelope(forms[token.form].extent,token));
  frame.extent[0]=Math.max(frame.extent[0],...originalBoxes.map(box=>2*Math.max(frame.center[0]-box.left,box.right-frame.center[0])+36));
  const zoom=Math.min(368/frame.extent[0],674/frame.extent[1]);
  frame.center[1]=payload.scene.extent[1]/2-674/(2*zoom);
  const half=Math.max(...originalBoxes.map(box=>(box.top-box.bottom)/2));
  const upper=payload.scene.extent[1]*.2-half;
  const lower=frame.center[1]-674/(2*zoom)+24/zoom+half;
  const ys=payload.stage.specimens.map(token=>token.at[1]),low=Math.min(...ys),high=Math.max(...ys);
  const spread=Math.min(2.6,Math.max(1,(upper-lower)/Math.max(1,high-low)));
  const middle=(upper+lower)/2;
  const boxes=payload.stage.specimens.map((token,id)=>{
    const at=[token.at[0],middle+(token.at[1]-(low+high)/2)*spread];
    forms[token.form].locations[id]=at;
    return rectangularEnvelope(forms[token.form].extent,{...token,at});
  });
  frame.extent[1]=Math.max(frame.extent[1],...boxes.map(box=>2*Math.max(frame.center[1]-box.bottom,box.top-frame.center[1])+36));
  const room=roomFor(payload);
  return {...payload,forms,scene:{...payload.scene,background:manifest.rooms[room].path,sprites,
    artEdition:ART_EDITION,worldFrame:frame,room}};
}
