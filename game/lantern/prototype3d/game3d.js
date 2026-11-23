// Lantern 3D — real 3D scene built entirely in code (three.js, MIT). No model or image files for the scene.
// Rules, generator, sound and text come from core.js.
"use strict";
const sysLang=(()=>{const l=(navigator.language||"en").toLowerCase();const c=l.split("-")[0];return l.startsWith("zh")?"zh-Hant":LANGS.some(x=>x[0]===c)?c:"en"})();
const fmtN=(k,n)=>tr(k).replace("{n}",n);
const S={lang:LANGS.some(x=>x[0]===load("lang",sysLang))?load("lang",sysLang):"en",inv:{hints:load("inv.hints",0),blasts:load("inv.blasts",1)},screen:"home",mode:"levels",level:load("level",1),p:null,cells:[],undo:[],hints:3,used:0,t0:0,tick:0,done:false,failed:false,
  run:0,auto:load("auto",true),sound:load("sound",true),music:load("music",true),hintCell:-1,at:[],shake:[],combo:0,introT:0,maxCount:0,rockClock:0,rockEvery:7,demo:true};
const MAXR=14,TOP=0.5;
const rnd=(a,b)=>a+Math.random()*(b-a), clamp=(v,a,b)=>Math.max(a,Math.min(b,v));

// ---------- 2D layers: sky behind, effects in front ----------
const sky=$("sky"),skx=sky.getContext("2d"),fx=$("fx"),fxx=fx.getContext("2d"),gl=$("gl");
let DPR=1,VW=0,VH=0;
const clouds=Array.from({length:9},()=>({x:Math.random(),y:.04+Math.random()*.42,w:.18+Math.random()*.3,h:.02+Math.random()*.035,v:.002+Math.random()*.004,a:.05+Math.random()*.08}));
const stars=Array.from({length:240},()=>({x:Math.random(),y:Math.random(),r:.5+Math.random()*1.3,p:Math.random()*7,s:.6+Math.random()*1.6}));
function drawSky(t){skx.setTransform(DPR,0,0,DPR,0,0);skx.clearRect(0,0,VW,VH);
  // moon
  const mx=VW*.8,my=VH*.11,mr=Math.min(VW,VH)*.07;skx.globalCompositeOperation="lighter";glow(skx,mx,my,mr*4,.22);skx.globalCompositeOperation="source-over";
  const g=skx.createRadialGradient(mx-mr*.3,my-mr*.3,mr*.1,mx,my,mr);g.addColorStop(0,"#fffdf0");g.addColorStop(1,"#f3e3b0");skx.fillStyle=g;skx.beginPath();skx.arc(mx,my,mr,0,7);skx.fill();
  skx.fillStyle="rgba(210,190,140,.35)";for(const[a,b,c]of[[-.3,.2,.2],[.25,-.25,.14],[.1,.35,.1]]){skx.beginPath();skx.arc(mx+a*mr,my+b*mr,c*mr,0,7);skx.fill()}
  for(const cl of clouds){if(!calm)cl.x=(cl.x+cl.v/60)%1.4;const g2=skx.createRadialGradient(0,0,0,0,0,1);g2.addColorStop(0,`rgba(170,180,255,${cl.a})`);g2.addColorStop(1,"rgba(170,180,255,0)");skx.save();skx.translate((cl.x-.2)*VW,cl.y*VH);skx.scale(cl.w*VW,cl.h*VH*3);skx.fillStyle=g2;skx.beginPath();skx.arc(0,0,1,0,7);skx.fill();skx.restore()}
  for(const s of stars){skx.globalAlpha=calm?.6:.3+.5*Math.sin(t/1000*s.s+s.p)**2;const im=s.r>1.35&&TEX.star_07;if(im){const z=s.r*11;skx.drawImage(im,s.x*VW-z/2,s.y*VH-z/2,z,z)}else{skx.fillStyle="#fff";skx.beginPath();skx.arc(s.x*VW,s.y*VH,s.r,0,7);skx.fill()}}
  skx.globalAlpha=1}

function drawFx(t,dt){fxx.setTransform(DPR,0,0,DPR,0,0);fxx.clearRect(0,0,VW,VH);fxx.globalCompositeOperation="lighter";
  for(let i=rings.length-1;i>=0;i--){const r=rings[i];r.age+=dt;if(r.age>r.life){rings.splice(i,1);continue}const u=r.age/r.life,rad=r.r0+(r.r1-r.r0)*(1-(1-u)*(1-u)),im=tex("circle_02",r.rgb);if(!im)continue;fxx.globalAlpha=1-u;fxx.drawImage(im,r.x-rad,r.y-rad,rad*2,rad*2)}
  for(let i=sparks.length-1;i>=0;i--){const s=sparks[i];s.age+=dt;if(s.age<0)continue;if(s.age>s.life){sparks.splice(i,1);continue}s.x+=s.vx*dt;s.y+=s.vy*dt;s.vy+=(s.g??220)*dt;s.vx*=.985;
    const al=1-s.age/s.life,im=s.tex&&tex(s.tex,s.col);
    if(im){s.rot+=s.spin*dt;fxx.globalAlpha=al;fxx.save();fxx.translate(s.x,s.y);fxx.rotate(s.rot);fxx.drawImage(im,-s.size/2,-s.size/2,s.size,s.size);fxx.restore()}
    else{fxx.globalAlpha=1;fxx.fillStyle=`rgba(${s.col},${al})`;fxx.beginPath();fxx.arc(s.x,s.y,s.r,0,7);fxx.fill()}}
  fxx.globalAlpha=1;fxx.globalCompositeOperation="source-over"}

// ---------- renderer, camera, lights ----------
const R=new THREE.WebGLRenderer({canvas:gl,antialias:true,alpha:true,powerPreference:"high-performance"});
R.shadowMap.enabled=true;R.toneMapping=THREE.ACESFilmicToneMapping;R.toneMappingExposure=1.3;R.setClearColor(0,0);
const scene=new THREE.Scene();
const cam=new THREE.PerspectiveCamera(30,1,.1,140);
scene.add(new THREE.HemisphereLight(0xa4b4ff,0x2a2452,1.35));
const moon=new THREE.DirectionalLight(0xcdd8ff,1.75);moon.position.set(-8,14,7);moon.castShadow=true;moon.shadow.mapSize.set(2048,2048);
Object.assign(moon.shadow.camera,{left:-10,right:10,top:10,bottom:-10,near:1,far:40});moon.shadow.bias=-.0004;moon.shadow.normalBias=.03;scene.add(moon);
const warm=new THREE.DirectionalLight(0xffb98a,.22);warm.position.set(5,5,10);scene.add(warm);

const M=(color,o={})=>new THREE.MeshStandardMaterial(Object.assign({color,roughness:.7,metalness:0},o));
const mesh=(g,m,x=0,y=0,z=0,sh=true)=>{const o=new THREE.Mesh(g,m);o.position.set(x,y,z);o.castShadow=sh;o.receiveShadow=true;return o};
function canvasTex(draw,s=128){const c=document.createElement("canvas");c.width=c.height=s;draw(c.getContext("2d"),s);const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;return t}
const glowTex=canvasTex((c,s)=>{const g=c.createRadialGradient(s/2,s/2,0,s/2,s/2,s/2);g.addColorStop(0,"rgba(255,225,160,1)");g.addColorStop(.3,"rgba(255,170,80,.55)");g.addColorStop(1,"rgba(255,120,40,0)");c.fillStyle=g;c.fillRect(0,0,s,s)});
const softTex=canvasTex((c,s)=>{const g=c.createRadialGradient(s/2,s/2,0,s/2,s/2,s/2);g.addColorStop(0,"rgba(0,0,0,.55)");g.addColorStop(1,"rgba(0,0,0,0)");c.fillStyle=g;c.fillRect(0,0,s,s)});
const wrap=(t,rx,ry)=>{t.wrapS=t.wrapT=THREE.RepeatWrapping;t.repeat.set(rx,ry);t.anisotropy=4;return t};
// grass: mottled base, thousands of blade strokes, clover dots
const grassTex=wrap(canvasTex((c,s)=>{c.fillStyle="#2a7a52";c.fillRect(0,0,s,s);
  for(let i=0;i<90;i++){c.fillStyle=`hsla(${rnd(130,165)},48%,${rnd(20,40)}%,.4)`;c.beginPath();c.arc(rnd(0,s),rnd(0,s),rnd(12,56),0,7);c.fill()}
  c.lineCap="round";for(let i=0;i<6500;i++){const x=rnd(0,s),y=rnd(0,s),l=rnd(3,10);c.strokeStyle=`hsla(${rnd(110,160)},${rnd(40,65)}%,${rnd(22,46)}%,.55)`;c.lineWidth=rnd(.8,2);c.beginPath();c.moveTo(x,y);c.lineTo(x+rnd(-3,3),y-l);c.stroke()}
  for(let i=0;i<260;i++){c.fillStyle=["#f4e9a8","#ffd0e0","#ffffff","#bfe6a0"][i%4];c.beginPath();c.arc(rnd(0,s),rnd(0,s),rnd(.8,1.8),0,7);c.fill()}},512),5,5);
// flagstones: Voronoi cells with dark joints and per-stone tone
function flagTex(s,cells,base,moss=true){return canvasTex(c=>{const pts=Array.from({length:cells},()=>[rnd(0,s),rnd(0,s),rnd(.86,1.06)]),im=c.createImageData(s,s),d=im.data;
  for(let y=0;y<s;y++)for(let x=0;x<s;x++){let a=1e9,b=1e9,ai=0;for(let i=0;i<cells;i++){const dx=x-pts[i][0],dy=y-pts[i][1],q=dx*dx+dy*dy;if(q<a){b=a;a=q;ai=i}else if(q<b)b=q}
    const e=Math.sqrt(b)-Math.sqrt(a),k=e<1.8?.55:e<3.6?.86:1,v=pts[ai][2]*k*(.96+Math.random()*.08),o=(y*s+x)*4;d[o]=base[0]*v;d[o+1]=base[1]*v;d[o+2]=base[2]*v;d[o+3]=255}
  c.putImageData(im,0,0);if(moss)for(let i=0;i<70;i++){c.fillStyle=`hsla(${rnd(110,150)},45%,${rnd(25,40)}%,.28)`;c.beginPath();c.arc(rnd(0,s),rnd(0,s),rnd(4,16),0,7);c.fill()}},s)}
const stoneTex=flagTex(384,95,[170,176,210]),stoneTex2=flagTex(192,26,[176,182,214]);
const waterTex=wrap(canvasTex((c,s)=>{c.fillStyle="#2f7fd6";c.fillRect(0,0,s,s);c.lineCap="round";for(let i=0;i<120;i++){const x=rnd(0,s),y=rnd(0,s),w=rnd(10,46);c.strokeStyle=`rgba(${rnd(150,230)|0},${rnd(215,250)|0},255,${rnd(.25,.75)})`;c.lineWidth=rnd(1,3.5);c.beginPath();c.moveTo(x,y);c.quadraticCurveTo(x+w/2,y+rnd(-7,7),x+w,y+rnd(-3,3));c.stroke()}
  for(let i=0;i<40;i++){c.fillStyle=`rgba(20,60,140,${rnd(.15,.4)})`;c.beginPath();c.ellipse(rnd(0,s),rnd(0,s),rnd(8,30),rnd(3,9),0,0,7);c.fill()}},256),2,2);
// glazed tile face: speckle, inset groove, corner highlight
const tileTex=(()=>{const t=canvasTex((c,s)=>{c.fillStyle="#fff";c.fillRect(0,0,s,s);const g=c.createLinearGradient(0,0,s,s);g.addColorStop(0,"rgba(255,255,255,0)");g.addColorStop(1,"rgba(0,0,30,.22)");c.fillStyle=g;c.fillRect(0,0,s,s);
  for(let i=0;i<900;i++){c.fillStyle=Math.random()<.5?`rgba(0,0,40,${rnd(.05,.2)})`:`rgba(255,255,255,${rnd(.2,.6)})`;c.fillRect(rnd(0,s),rnd(0,s),rnd(1,2.6),rnd(1,2.6))}
  c.lineWidth=4;c.strokeStyle="rgba(0,0,40,.3)";c.beginPath();c.roundRect(s*.17,s*.17,s*.66,s*.66,s*.1);c.stroke();c.lineWidth=2;c.strokeStyle="rgba(255,255,255,.55)";c.beginPath();c.roundRect(s*.19,s*.19,s*.66,s*.66,s*.1);c.stroke();
  c.fillStyle="rgba(255,255,255,.5)";c.beginPath();c.ellipse(s*.33,s*.3,s*.1,s*.035,-.6,0,7);c.fill();
  for(const[x,y]of[[.5,.26],[.5,.74],[.26,.5],[.74,.5]]){c.fillStyle="rgba(0,0,40,.22)";c.beginPath();c.arc(s*x,s*y,2.2,0,7);c.fill()}},128);t.wrapS=t.wrapT=THREE.RepeatWrapping;t.repeat.set(1.1,1.1);t.offset.set(.5,.5);return t})();
const woodTex=wrap(canvasTex((c,s)=>{c.fillStyle="#a8743c";c.fillRect(0,0,s,s);for(let i=0;i<150;i++){const y=rnd(0,s);c.strokeStyle=`rgba(${rnd(60,110)|0},${rnd(30,60)|0},${rnd(8,30)|0},${rnd(.25,.7)})`;c.lineWidth=rnd(.6,2.6);c.beginPath();c.moveTo(0,y);c.bezierCurveTo(s*.3,y+rnd(-5,5),s*.7,y+rnd(-5,5),s,y+rnd(-2,2));c.stroke()}
  for(let i=0;i<5;i++){const x=rnd(0,s),y=rnd(0,s);for(let r=9;r>1;r-=2){c.strokeStyle=`rgba(70,36,12,${rnd(.3,.6)})`;c.lineWidth=1;c.beginPath();c.ellipse(x,y,r*1.6,r,0,0,7);c.stroke()}}},256),2,1);
const feltTex=wrap(canvasTex((c,s)=>{c.fillStyle="#1b1f55";c.fillRect(0,0,s,s);for(let y=0;y<4;y++)for(let x=0;x<4;x++){const px=(x+.5)*s/4,py=(y+.5)*s/4;c.fillStyle="rgba(244,200,96,.38)";c.beginPath();for(let k=0;k<8;k++){const a=k*Math.PI/4,r=k%2?2:6;c.lineTo(px+Math.cos(a)*r,py+Math.sin(a)*r)}c.fill();c.strokeStyle="rgba(120,130,220,.18)";c.lineWidth=1;c.strokeRect(x*s/4+3,y*s/4+3,s/4-6,s/4-6)}},128),6,6);
const runeTex=canvasTex((c,s)=>{const h=s/2;c.fillStyle="#8f95c4";c.fillRect(0,0,s,s);for(let i=0;i<2500;i++){c.fillStyle=`rgba(${Math.random()<.5?"30,30,80":"255,255,255"},${rnd(.05,.2)})`;c.fillRect(rnd(0,s),rnd(0,s),2,2)}
  c.strokeStyle="#f4c860";for(const[r,w]of[[.46,5],[.36,2],[.2,3]]){c.lineWidth=w;c.beginPath();c.arc(h,h,s*r,0,7);c.stroke()}c.lineWidth=2.5;c.beginPath();for(let k=0;k<=16;k++){const a=k*Math.PI/8*3;c.lineTo(h+Math.cos(a)*s*.36,h+Math.sin(a)*s*.36)}c.stroke();
  for(let k=0;k<24;k++){const a=k*Math.PI/12;c.beginPath();c.moveTo(h+Math.cos(a)*s*.39,h+Math.sin(a)*s*.39);c.lineTo(h+Math.cos(a)*s*.44,h+Math.sin(a)*s*.44);c.stroke()}},256);
const glowSprite=(scale,op=.6,color=0xffffff)=>{const s=new THREE.Sprite(new THREE.SpriteMaterial({map:glowTex,color,blending:THREE.AdditiveBlending,depthWrite:false,transparent:true,opacity:op}));s.scale.setScalar(scale);return s};

// ---------- world: floating island garden ----------
const world=new THREE.Group();scene.add(world);
{ // island
  const grass=mesh(new THREE.CylinderGeometry(12,11.6,.6,56),[M(0x3a6a44,{roughness:1}),M(0xffffff,{roughness:.95,map:grassTex}),M(0x3a2c2a)],0,-.3,0,false);world.add(grass);
  const lip=mesh(new THREE.CylinderGeometry(11.6,10.4,.9,56),M(0x6a4a3a,{roughness:1}),0,-1.05,0,false);world.add(lip);
  const under=new THREE.ConeGeometry(10.4,9,11,3);const pa=under.attributes.position;for(let i=0;i<pa.count;i++){if(pa.getY(i)<4.4){pa.setX(i,pa.getX(i)*rnd(.8,1.15));pa.setZ(i,pa.getZ(i)*rnd(.8,1.15))}}under.computeVertexNormals();
  const um=mesh(under,M(0x4a3a5c,{roughness:1,flatShading:true}),0,-6,0,false);um.rotation.x=Math.PI;world.add(um);
  // lighter grass patches
  const pm=M(0x49b072,{roughness:.95,transparent:true,opacity:.35});for(let i=0;i<10;i++){const a=rnd(0,6.28),r=rnd(2,10.5),p=mesh(new THREE.CircleGeometry(rnd(.7,1.9),18),pm,Math.cos(a)*r,.004+i*.0004,Math.sin(a)*r,false);p.rotation.x=-Math.PI/2;world.add(p)}
  // pond with lily pads
  const pond=mesh(new THREE.CircleGeometry(2.7,40),M(0xffffff,{map:waterTex,roughness:.12,metalness:.35,emissive:0x12305e,emissiveIntensity:.9}),-4.6,.012,-7.2,false);pond.rotation.x=-Math.PI/2;world.add(pond);world.userData.pond=pond;
  const rim=mesh(new THREE.TorusGeometry(2.75,.16,8,40),M(0x8b90ad,{roughness:.9,flatShading:true}),-4.6,.03,-7.2);rim.rotation.x=Math.PI/2;world.add(rim);
  for(let i=0;i<5;i++){const a=rnd(0,6.28),r=rnd(.4,2),l=mesh(new THREE.CircleGeometry(rnd(.22,.36),12,0,5.6),M(0x4fb673),-4.6+Math.cos(a)*r,.03,-7.2+Math.sin(a)*r,false);l.rotation.x=-Math.PI/2;l.rotation.z=rnd(0,6);world.add(l)}
  world.userData.ripples=[0,1,2].map(i=>{const r=mesh(new THREE.RingGeometry(.9,1,32),new THREE.MeshBasicMaterial({color:0xcfe8ff,transparent:true,opacity:.4,depthWrite:false}),-4.6,.02,-7.2,false);r.rotation.x=-Math.PI/2;r.receiveShadow=false;world.add(r);return r});
  // trees
  const trunk=M(0x6b4630,{roughness:1}),leafs=[M(0x1f7a5a,{flatShading:true,roughness:.9}),M(0x2a9168,{flatShading:true,roughness:.9}),M(0x7fbf5a,{flatShading:true,roughness:.9}),M(0xe58bb0,{flatShading:true,roughness:.9})];
  const tree=(x,z,s,kind)=>{const g=new THREE.Group();g.add(mesh(new THREE.CylinderGeometry(.14*s,.2*s,1.2*s,7),trunk,0,.6*s,0));
    if(kind===3){for(let i=0;i<5;i++)g.add(mesh(new THREE.IcosahedronGeometry(rnd(.5,.8)*s,0),leafs[3],rnd(-.5,.5)*s,(1.5+rnd(0,.7))*s,rnd(-.5,.5)*s))}
    else for(let i=0;i<3;i++)g.add(mesh(new THREE.ConeGeometry((1-.22*i)*s,1.25*s,7),leafs[(kind+i)%3],0,(1.45+i*.72)*s,0));
    g.position.set(x,0,z);g.rotation.y=rnd(0,6);world.add(g);return g};
  world.userData.trees=[[-8.3,-4.2,1.25,0],[-6.6,-9,1.5,1],[-1,-10.2,1.7,0],[3.4,-9.4,1.2,3],[7.2,-7.3,1.55,1],[9.4,-2.6,1.2,0],[-10,1.2,1.1,3],[10.2,2.8,1.25,1],[-9,6.2,1,0],[8.8,7,1.05,3]].map(a=>tree(...a));
  // boulders
  const bm=M(0x8a8fae,{flatShading:true,roughness:.95});for(const[x,z,s]of[[-6.2,-2,.5],[6.4,-4.6,.65],[5.6,5.4,.4],[-5.8,5.6,.55],[1.8,-8,.5],[-2.4,7.4,.35],[7.6,.8,.45]]){const b=mesh(new THREE.IcosahedronGeometry(s,0),bm,x,s*.5,z);b.scale.y=.75;b.rotation.set(rnd(0,3),rnd(0,3),0);world.add(b)}
  // grass tufts and flowers (instanced)
  const N=2600,tg=new THREE.ConeGeometry(.06,.34,4);tg.translate(0,.17,0);const tufts=new THREE.InstancedMesh(tg,M(0xffffff,{roughness:1}),N),d=new THREE.Object3D(),col=new THREE.Color();
  for(let i=0;i<N;i++){const a=rnd(0,6.28),r=Math.sqrt(rnd(.02,1))*11.6;d.position.set(Math.cos(a)*r,0,Math.sin(a)*r);d.rotation.set(rnd(-.25,.25),rnd(0,6),rnd(-.25,.25));d.scale.set(rnd(.7,1.6),rnd(.6,1.9),rnd(.7,1.6));d.updateMatrix();tufts.setMatrixAt(i,d.matrix);tufts.setColorAt(i,col.setHSL(rnd(.33,.42),rnd(.45,.65),rnd(.3,.48)))}
  tufts.receiveShadow=true;world.add(tufts);
  const F=320,fg=new THREE.IcosahedronGeometry(.07,0),fl=new THREE.InstancedMesh(fg,M(0xffffff,{roughness:.6,emissive:0x221122}),F);
  for(let i=0;i<F;i++){const a=rnd(0,6.28),r=Math.sqrt(rnd(.05,1))*11.4;d.position.set(Math.cos(a)*r,rnd(.2,.34),Math.sin(a)*r);d.rotation.set(0,0,0);d.scale.setScalar(rnd(.7,1.4));d.updateMatrix();fl.setMatrixAt(i,d.matrix);fl.setColorAt(i,col.set([0xffd166,0xff8fb3,0xffffff,0xc9a3ff][i%4]))}
  world.add(fl);
  // bushes, mushrooms, pebbles
  const bushM=[M(0x2f9a63,{flatShading:true,roughness:.9}),M(0x57b86a,{flatShading:true,roughness:.9})];
  for(let i=0;i<16;i++){const a=rnd(0,6.28),r=rnd(6.6,11),g=new THREE.Group();for(let j=0;j<4;j++)g.add(mesh(new THREE.IcosahedronGeometry(rnd(.28,.5),1),bushM[j%2],rnd(-.4,.4),rnd(.2,.5),rnd(-.4,.4)));for(let j=0;j<3;j++)g.add(mesh(new THREE.SphereGeometry(.06,6,5),M(0xff6b8a,{emissive:0x40101c}),rnd(-.5,.5),rnd(.4,.75),rnd(-.5,.5),false));g.position.set(Math.cos(a)*r,0,Math.sin(a)*r);world.add(g)}
  const capM=M(0xe2473a,{roughness:.5}),stemM=M(0xf3ead8),dotM=M(0xffffff);
  for(let i=0;i<22;i++){const a=rnd(0,6.28),r=rnd(5.6,11.2),k=rnd(.7,1.4),g=new THREE.Group();g.add(mesh(new THREE.CylinderGeometry(.045,.06,.18,7),stemM,0,.09,0));const cap=mesh(new THREE.SphereGeometry(.13,10,6,0,6.3,0,1.6),capM,0,.17,0);g.add(cap);for(let j=0;j<4;j++){const d=mesh(new THREE.SphereGeometry(.022,5,4),dotM,Math.cos(j*1.6)*.07,.26,Math.sin(j*1.6)*.07,false);g.add(d)}g.scale.setScalar(k);g.position.set(Math.cos(a)*r,0,Math.sin(a)*r);world.add(g)}
  const P=220,pg=new THREE.DodecahedronGeometry(.09,0),peb=new THREE.InstancedMesh(pg,M(0xffffff,{roughness:.95,flatShading:true}),P);
  for(let i=0;i<P;i++){const a=rnd(0,6.28),r=Math.sqrt(rnd(.03,1))*11.5;d.position.set(Math.cos(a)*r,.04,Math.sin(a)*r);d.rotation.set(rnd(0,3),rnd(0,3),0);d.scale.set(rnd(.6,1.8),rnd(.4,.9),rnd(.6,1.8));d.updateMatrix();peb.setMatrixAt(i,d.matrix);peb.setColorAt(i,col.setHSL(.64,rnd(.08,.2),rnd(.42,.7)))}
  peb.castShadow=true;peb.receiveShadow=true;world.add(peb);
}
// fireflies and far-away sky lanterns
const flies=Array.from({length:46},()=>{const s=glowSprite(rnd(.18,.34),.9,0xd8ff9a);s.userData={x:rnd(-10,10),y:rnd(.5,3.2),z:rnd(-10,9),p:rnd(0,7),sp:rnd(.3,.9)};scene.add(s);return s});
const farL=Array.from({length:16},()=>{const s=glowSprite(rnd(.9,1.8),.85,0xffc890);const a=rnd(0,6.28),r=rnd(15,34);s.userData={x:Math.cos(a)*r,z:-Math.abs(Math.sin(a)*r)-4,y:rnd(-4,18),v:rnd(.25,.6),p:rnd(0,7)};scene.add(s);return s});

// ---------- lantern model ----------
const LG={body:(()=>{const p=[];for(let i=0;i<=14;i++){const u=i/14;p.push(new THREE.Vector2(.1+.25*Math.pow(Math.sin(Math.PI*u),.75),-.3+.6*u))}return new THREE.LatheGeometry(p,24)})(),
  rib:new THREE.TorusGeometry(.345,.012,6,36),cap:new THREE.CylinderGeometry(.13,.15,.08,18),ring:new THREE.TorusGeometry(.145,.016,6,20),
  handle:new THREE.TorusGeometry(.075,.013,6,14,Math.PI),cord:new THREE.CylinderGeometry(.008,.008,.16,5),bead:new THREE.SphereGeometry(.035,10,8),tassel:new THREE.ConeGeometry(.035,.13,8)};
const LM={good:M(0xff4a1e,{emissive:0xff5a14,emissiveIntensity:1.75,roughness:.55}),bad:M(0x7d82a6,{emissive:0x20244a,emissiveIntensity:.6,roughness:.7}),
  rib:M(0x9c1f18,{roughness:.6}),ribBad:M(0x3d4066),wood:M(0x4a2414,{roughness:.6}),gold:M(0xf4c860,{roughness:.3,metalness:.7,emissive:0x5a3a08}),red:M(0xe2473a,{emissive:0x6a1208})};
function makeLantern(withLight=true){const g=new THREE.Group(),body=mesh(LG.body,LM.good);g.add(body);const ribs=[];
  for(let i=0;i<3;i++){const r=mesh(LG.rib,LM.rib);r.scale.set(1.01,.87,1);r.rotation.y=i*Math.PI/3;g.add(r);ribs.push(r)}
  for(const s of[1,-1]){g.add(mesh(LG.cap,LM.wood,0,s*.31,0));const rg=mesh(LG.ring,LM.gold,0,s*.31,0);rg.rotation.x=Math.PI/2;g.add(rg)}
  g.add(mesh(LG.handle,LM.gold,0,.35,0));g.add(mesh(LG.cord,LM.gold,0,-.43,0));g.add(mesh(LG.bead,LM.red,0,-.52,0));const ts=mesh(LG.tassel,LM.red,0,-.61,0);ts.rotation.x=Math.PI;g.add(ts);
  const gs=glowSprite(2.6,.62);g.add(gs);g.userData={body,ribs,gs,li:0,lit:withLight,isBad:false};return g}
const LIGHTS=Array.from({length:8},()=>{const l=new THREE.PointLight(0xffa850,0,4.6,1.6);scene.add(l);return l});
function setBad(l,b){const u=l.userData;if(u.isBad===b)return;u.isBad=b;u.body.material=b?LM.bad:LM.good;for(const r of u.ribs)r.material=b?LM.ribBad:LM.rib}

// ---------- board ----------
const PALC=[[0x35b3a8,0x1f7a73],[0xa56bd6,0x6f3f9c],[0xec6f8e,0xab4562],[0x5f86ea,0x3a57ad],[0x86bf5c,0x557f38],[0xe3bd6a,0xa5843c],[0x52bdea,0x2f83ad],[0x98a2cc,0x5f6896]];
const tileGeo=(()=>{const h=.4,r=.13,s=new THREE.Shape();s.moveTo(-h+r,-h);s.lineTo(h-r,-h);s.quadraticCurveTo(h,-h,h,-h+r);s.lineTo(h,h-r);s.quadraticCurveTo(h,h,h-r,h);s.lineTo(-h+r,h);s.quadraticCurveTo(-h,h,-h,h-r);s.lineTo(-h,-h+r);s.quadraticCurveTo(-h,-h,-h+r,-h);
  const g=new THREE.ExtrudeGeometry(s,{depth:.14,bevelEnabled:true,bevelThickness:.05,bevelSize:.05,bevelSegments:4,curveSegments:6});g.rotateX(-Math.PI/2);g.translate(0,.05,0);return g})();
const tileMat=PALC.map(([a])=>[0,.07].map(k=>{const c=new THREE.Color(a).lerp(new THREE.Color(0xffffff),k);return M(c,{roughness:.38,metalness:.05,map:tileTex,emissive:c,emissiveMap:tileTex,emissiveIntensity:.34})}));
const plateMat=PALC.map(([,b])=>M(b,{roughness:.8}));
const markGeo=new THREE.BoxGeometry(.42,.035,.1),markMat=new THREE.MeshBasicMaterial({color:0x0c1034,transparent:true,opacity:.88}),markRimGeo=new THREE.BoxGeometry(.47,.03,.15),markRimMat=new THREE.MeshBasicMaterial({color:0xffffff,transparent:true,opacity:.55});
const board=new THREE.Group();scene.add(board);let cellsO=[];
for(const g of[tileGeo,markGeo,markRimGeo,...Object.values(LG)])g.userData.shared=true;
for(const m of[markMat,markRimMat,...Object.values(LM),...tileMat.flat(),...plateMat])m.userData.shared=true;
function dispose(obj){obj.traverse(o=>{if(o.geometry&&!o.geometry.userData.shared)o.geometry.dispose();const ms=Array.isArray(o.material)?o.material:o.material?[o.material]:[];for(const m of ms)if(!m.userData.shared)m.dispose()})}
function drop(parent,obj){parent.remove(obj);dispose(obj)}
const hintRing=mesh(new THREE.TorusGeometry(.4,.04,8,36),new THREE.MeshBasicMaterial({color:0xffffff,transparent:true}),0,0,0,false);hintRing.rotation.x=Math.PI/2;hintRing.visible=false;scene.add(hintRing);
const badRingGeo=new THREE.TorusGeometry(.43,.035,8,36),badRingMat=new THREE.MeshBasicMaterial({color:0xff5d6c,transparent:true});badRingGeo.userData.shared=true;badRingMat.userData.shared=true;
const cx=(k,n)=>k%n-(n-1)/2, cz=(k,n)=>Math.floor(k/n)-(n-1)/2;
function buildBoard(){while(board.children.length)drop(board,board.children[0]);if(board.userData.felt)board.userData.felt.dispose();for(const b of beams)b.mat.dispose();beams.length=0;cellsO=[];const n=S.p.n,g=S.p.g;
  // paved plaza under the board and keeper, wooden frame with gold corners, star-patterned felt
  const R1=(n/2+1.15)*1.42,pl1=mesh(new THREE.CircleGeometry(R1,48),M(0xffffff,{map:stoneTex,roughness:.9}),0,.012,0,false);pl1.rotation.x=-Math.PI/2;board.add(pl1);
  const pl2=mesh(new THREE.CircleGeometry(2.1,36),M(0xffffff,{map:stoneTex2,roughness:.9}),0,.014,n/2+3,false);pl2.rotation.x=-Math.PI/2;board.add(pl2);
  for(let i=0;i<26;i++){const a=i/26*6.283,st=mesh(new THREE.DodecahedronGeometry(rnd(.16,.26),0),M(0x8b90ad,{flatShading:true,roughness:.95}),Math.cos(a)*(R1+.1),.08,Math.sin(a)*(R1+.1));st.scale.y=.6;st.rotation.y=rnd(0,3);board.add(st)}
  board.add(mesh(new THREE.BoxGeometry(n+1.15,.22,n+1.15),M(0xffffff,{map:woodTex,roughness:.7}),0,.11,0));
  for(const[sx,sz]of[[-1,-1],[1,-1],[-1,1],[1,1]])board.add(mesh(new THREE.BoxGeometry(.42,.25,.42),M(0xf4c860,{roughness:.3,metalness:.75}),sx*(n/2+.4),.11,sz*(n/2+.4)));
  const felt=feltTex.clone();felt.needsUpdate=true;board.userData.felt=felt;felt.repeat.set(n+.8,n+.8);board.add(mesh(new THREE.BoxGeometry(n+.8,.34,n+.8),[M(0x1d2152),M(0x1d2152),M(0xffffff,{map:felt,roughness:.85}),M(0x1d2152),M(0x1d2152),M(0x1d2152)],0,.17,0));
  // torii gate behind the board
  {const red=M(0xc8382e,{roughness:.6}),blk=M(0x2a1c1c),g=new THREE.Group(),w=n/2+.4;for(const sx of[-1,1]){g.add(mesh(new THREE.CylinderGeometry(.13,.16,2.9,10),red,sx*w,1.45,0));g.add(mesh(new THREE.CylinderGeometry(.2,.22,.3,10),blk,sx*w,.15,0))}
    g.add(mesh(new THREE.BoxGeometry(w*2+1.5,.2,.34),blk,0,3.02,0));g.add(mesh(new THREE.BoxGeometry(w*2+1.2,.18,.28),red,0,2.84,0));g.add(mesh(new THREE.BoxGeometry(w*2+.6,.16,.22),red,0,2.3,0));g.add(mesh(new THREE.BoxGeometry(.2,.4,.2),red,0,2.58,0));g.position.set(0,0,-(n/2+2.3));board.add(g)}
  for(let k=0;k<n*n;k++){const x=k%n,y=Math.floor(k/n),rg=g[k]%8,L=x===0||g[k-1]!==g[k],Rr=x===n-1||g[k+1]!==g[k],Tp=y===0||g[k-n]!==g[k],B=y===n-1||g[k+n]!==g[k],i=.07;
    const w=1-(L?i:0)-(Rr?i:0),d=1-(Tp?i:0)-(B?i:0),pl=mesh(new THREE.BoxGeometry(w,.12,d),plateMat[rg],cx(k,n)+((L?i:0)-(Rr?i:0))/2,.4,cz(k,n)+((Tp?i:0)-(B?i:0))/2,false);board.add(pl);
    const tile=mesh(tileGeo,tileMat[rg][(x+y)%2],cx(k,n),.26,cz(k,n),false);board.add(tile);
    const ring=mesh(badRingGeo,badRingMat,cx(k,n),TOP+.03,cz(k,n),false);ring.rotation.x=Math.PI/2;ring.visible=false;board.add(ring);
    cellsO.push({tile,x:cx(k,n),z:cz(k,n),mark:null,lan:null,ring,rise:0})}
  // stone lamp posts at the corners
  const st=M(0x8b90ad,{roughness:.9,flatShading:true}),lit=M(0xffd58a,{emissive:0xffa63d,emissiveIntensity:2.2});
  for(const[sx,sz]of[[-1,-1],[1,-1],[-1,1],[1,1]]){const p=new THREE.Group(),h=n/2+1.25;p.add(mesh(new THREE.CylinderGeometry(.2,.26,.2,6),st,0,.1,0));p.add(mesh(new THREE.CylinderGeometry(.09,.11,.7,6),st,0,.55,0));p.add(mesh(new THREE.BoxGeometry(.34,.3,.34),lit,0,1.05,0));p.add(mesh(new THREE.ConeGeometry(.36,.26,4),st,0,1.33,0));p.children[3].rotation.y=Math.PI/4;const gs=glowSprite(1.5,.45);gs.position.y=1.05;p.add(gs);p.position.set(sx*h,0,sz*h);board.add(p)}
  keeper.position.set(0,0,n/2+3)}
function sync(k){const o=cellsO[k],v=S.cells[k];
  if(v!==1&&o.mark){drop(board,o.mark);o.mark=null}
  if(v!==2&&o.lan&&!o.rise){drop(board,o.lan);o.lan=null}
  if(v===1&&!o.mark){const m=new THREE.Group();for(const a of[1,-1]){const r=new THREE.Mesh(markRimGeo,markRimMat);r.rotation.y=a*Math.PI/4;m.add(r)}for(const a of[1,-1]){const b=new THREE.Mesh(markGeo,markMat);b.rotation.y=a*Math.PI/4;b.position.y=.006;m.add(b)}m.position.set(o.x,TOP+.02,o.z);board.add(m);o.mark=m}
  if(v===2&&!o.lan){o.lan=makeLantern();o.lan.position.set(o.x,TOP+.55,o.z);board.add(o.lan)}}
const syncAll=()=>{for(let k=0;k<cellsO.length;k++)sync(k)};

// ---------- keeper and rocks ----------
const keeper=new THREE.Group();keeper.scale.setScalar(1.1);scene.add(keeper);const KP={};{const kl=new THREE.PointLight(0xffc890,2.2,6,1.6);kl.position.set(0,1.2,1.6);keeper.add(kl)}
{ keeper.add(mesh(new THREE.CylinderGeometry(.95,1.08,.3,28),M(0x8f95c4,{roughness:.9}),0,.15,0));keeper.add(mesh(new THREE.CylinderGeometry(.8,.8,.06,28),[M(0xc9a45a,{roughness:.35,metalness:.6}),M(0xffffff,{map:runeTex,roughness:.7}),M(0xc9a45a)],0,.31,0));
  const b=new THREE.Group();b.position.y=.33;keeper.add(b);KP.body=b;
  const robe=M(0x4f63e0,{roughness:.6}),skin=M(0xffd9b5,{roughness:.7}),dark=M(0x1a1c3a),straw=M(0xe8c36e,{roughness:.8});KP.skin=skin;
  for(const s of[1,-1])b.add(mesh(new THREE.CapsuleGeometry(.075,.12,4,8),M(0x2d356e),s*.11,.12,0));
  b.add(mesh(new THREE.CapsuleGeometry(.25,.26,6,16),robe,0,.5,0));
  { // costume details: hem trim, scarf, robe stars, shoes, belt lantern, eyebrows
    const hem=mesh(new THREE.TorusGeometry(.235,.03,8,22),M(0xf2f2ff),0,.27,0);hem.rotation.x=Math.PI/2;b.add(hem);
    const scarf=mesh(new THREE.TorusGeometry(.17,.06,8,20),LM.red,0,.8,0);scarf.rotation.x=Math.PI/2;b.add(scarf);const tail=mesh(new THREE.BoxGeometry(.09,.26,.03),LM.red,.13,.68,.2);tail.rotation.z=-.25;b.add(tail);
    for(const[x,y]of[[-.1,.58],[.09,.5],[-.03,.4]]){const st=mesh(new THREE.OctahedronGeometry(.03,0),LM.gold,x,y,.24,false);st.scale.z=.3;b.add(st)}
    for(const sx of[1,-1]){const sh=mesh(new THREE.SphereGeometry(.09,10,8),M(0x3a2414),sx*.11,.04,.05);sh.scale.set(1,.6,1.4);b.add(sh)}
    const bl=makeLantern(false);bl.scale.setScalar(.22);bl.position.set(-.27,.36,.12);b.add(bl) }const belt=mesh(new THREE.TorusGeometry(.245,.035,8,20),LM.gold,0,.42,0);belt.rotation.x=Math.PI/2;b.add(belt);
  const head=new THREE.Group();head.position.y=1.02;head.scale.setScalar(1.3);b.add(head);KP.head=head;head.add(mesh(new THREE.SphereGeometry(.23,20,16),skin));
  KP.eyes=[1,-1].map(s=>{const e=mesh(new THREE.SphereGeometry(.032,10,8),dark,s*.085,.02,.205,false);head.add(e);return e});
  for(const s of[1,-1]){const c=mesh(new THREE.SphereGeometry(.04,8,6),M(0xff9aa8),s*.14,-.05,.175,false);c.scale.z=.4;head.add(c)}
  KP.brows=[1,-1].map(s=>{const e=mesh(new THREE.BoxGeometry(.07,.016,.02),dark,s*.085,.075,.21,false);head.add(e);return e});const hair=mesh(new THREE.SphereGeometry(.235,16,10,0,6.3,0,1.25),M(0x2a1c1c),0,.01,-.02);head.add(hair);
  KP.mouth=mesh(new THREE.TorusGeometry(.035,.012,6,12,Math.PI),dark,0,-.07,.215,false);KP.mouth.rotation.z=Math.PI;head.add(KP.mouth);
  const hat=new THREE.Group();hat.position.set(0,.13,-.13);hat.rotation.x=-.75;head.add(hat);KP.hat=hat;hat.add(mesh(new THREE.ConeGeometry(.4,.2,22),straw,0,.07,0));hat.add(mesh(new THREE.ConeGeometry(.14,.12,12),straw,0,.2,0));{const band=mesh(new THREE.TorusGeometry(.2,.022,6,20),LM.red,0,.085,0);band.rotation.x=Math.PI/2;hat.add(band);for(let i=0;i<10;i++){const ln=mesh(new THREE.BoxGeometry(.012,.01,.3),M(0xb89444),0,.075,0,false);ln.rotation.y=i*.628;ln.rotation.x=.42;ln.position.set(Math.sin(i*.628)*.19,.07,Math.cos(i*.628)*.19);hat.add(ln)}}
  KP.arms=[1,-1].map(s=>{const a=new THREE.Group();a.position.set(s*.25,.72,0);a.add(mesh(new THREE.CapsuleGeometry(.055,.74,4,8),robe,0,.42,0));a.add(mesh(new THREE.SphereGeometry(.07,10,8),skin,0,.84,0));a.rotation.z=-s*.5;a.rotation.x=.22;b.add(a);return a});b.rotation.x=-.5;
  const pg=new THREE.Group();keeper.add(pg);KP.plank=pg;pg.add(mesh(new THREE.BoxGeometry(2.5,.1,.56),M(0xffffff,{map:woodTex,roughness:.8}),0,0,0));for(const sx of[-1.15,1.15])pg.add(mesh(new THREE.BoxGeometry(.12,.13,.6),LM.gold,sx,0,0));for(const s of[1,-1])pg.add(mesh(new THREE.BoxGeometry(.08,.14,.6),M(0x6b4424),s*.9,0,0));
  KP.rocks=new THREE.Group();KP.rocks.position.y=.05;pg.add(KP.rocks);
  const sh=mesh(new THREE.PlaneGeometry(1.7,1.2),new THREE.MeshBasicMaterial({map:softTex,transparent:true,depthWrite:false}),0,.345,0,false);sh.rotation.x=-Math.PI/2;sh.receiveShadow=false;keeper.add(sh)}
const rockMat=[0x8d93ad,0x767b96,0xa3a8c2].map(c=>M(c,{flatShading:true,roughness:.95})),rockGeo=[new THREE.IcosahedronGeometry(.2,0),new THREE.DodecahedronGeometry(.2,0)];for(const x of[...rockMat,...rockGeo])x.userData.shared=true;
let rocks=[],flying=[],K={dip:0,dipV:0,hop:0,hopV:0,cheer:0,squash:0};
const slot=i=>{let r=0,left=i;for(;;){const c=r%2?4:5;if(left<c)return{x:(left-(c-1)/2)*.46,y:.16+r*.31,z:rnd(-.07,.07)};left-=c;r++}};
const resting=()=>rocks.length;
function dropRock(){if(rocks.length>=MAXR)return;const i=rocks.length,sl=slot(i),m=mesh(rockGeo[i%2],rockMat[i%3]);m.scale.set(rnd(.85,1.25),rnd(.8,1.1),rnd(.85,1.25));m.rotation.set(rnd(0,6),rnd(0,6),rnd(0,6));
  m.position.set(sl.x,7.5,sl.z);m.userData={ty:sl.y,vy:0,landed:false,sq:0,by:m.scale.y};KP.rocks.add(m);rocks.push(m);meter()}
function blast(cnt){for(let i=0;i<cnt&&rocks.length;i++){const m=rocks.pop(),w=new THREE.Vector3();m.getWorldPosition(w);KP.rocks.remove(m);m.position.copy(w);scene.add(m);
    m.userData={vx:rnd(-4,4),vy:rnd(5,8),vz:rnd(1,5),sx:rnd(-9,9),sz:rnd(-9,9),age:0};flying.push(m);const p=scr(w.x,w.y,w.z);burst(p.x,p.y,10,"255,225,160",170);rings.push({x:p.x,y:p.y,age:0,life:.4,r0:8,r1:60,rgb:"255,230,170"})}
  if(cnt){K.hopV=3.2;clip("mark",.9,.5)||tone(240,.12,"triangle",.08)}meter()}
function meter(){const L=rocks.length/MAXR,el=$("loadbar");el.firstElementChild.style.width=Math.round(L*100)+"%";el.classList.toggle("hot",L>=.72&&!S.done)}

// ---------- camera ----------
const camBase=new THREE.Vector3(),camTarget=new THREE.Vector3(),v3=new THREE.Vector3();let trauma=0,zoomPulse=0;
function scr(x,y,z){v3.set(x,y,z).project(cam);return{x:(v3.x*.5+.5)*VW,y:(-v3.y*.5+.5)*VH}}
// Fit the board and keeper into the free area of the screen: between the top and bottom HUD in portrait,
// beside the side panel in landscape. The panel side is read from the DOM so RTL works unchanged.
// Portrait only. On a wide window the game lives in a centred phone-shaped column; the free area for the
// board is whatever lies between the top HUD and the bottom controls, read from the DOM.
function freeRect(){const home=S.screen==="home",cw=Math.min(VW,VH*.62),x0=(VW-cw)/2,top=$(home?"t-rules":"meter").getBoundingClientRect(),bot=$(home?"play":"tools").getBoundingClientRect();
  const y0=top.bottom+(home?4:2),y1=bot.top-(home?8:2);return{x0,x1:x0+cw,y0,y1:Math.max(y0+120,y1)}}
function fit(){const n=S.p?S.p.n:5,home=S.screen==="home",fr=freeRect(),aw=fr.x1-fr.x0,ah=fr.y1-fr.y0,h=n/2,kz=h+3;
  const m=home?.9:.52,pts=[[-h-m,.3,-h-m],[h+m,.3,-h-m],[-h-m,.3,h+m],[h+m,.3,h+m],[-1.3,.2,kz+.9],[1.3,.2,kz+.9],[0,1.2,kz]];
  const pitch=home?.66:.93;camTarget.set(0,.5,.9);cam.aspect=VW/VH;cam.clearViewOffset();
  for(let D=9;D<90;D+=.5){camBase.set(0,camTarget.y+Math.sin(pitch)*D,camTarget.z+Math.cos(pitch)*D);cam.position.copy(camBase);cam.lookAt(camTarget);cam.updateProjectionMatrix();cam.updateMatrixWorld();
    let x0=1e9,x1=-1e9,y0=1e9,y1=-1e9;for(const p of pts){const q=scr(...p);x0=Math.min(x0,q.x);x1=Math.max(x1,q.x);y0=Math.min(y0,q.y);y1=Math.max(y1,q.y)}
    if(x1-x0<=aw&&y1-y0<=ah){cam.setViewOffset(VW,VH,Math.round((x0+x1)/2-(fr.x0+fr.x1)/2),Math.round((y0+y1)/2-(fr.y0+fr.y1)/2),VW,VH);cam.updateProjectionMatrix();break}}}
function layout(){DPR=Math.min(window.devicePixelRatio||1,2);VW=innerWidth;VH=innerHeight;for(const c of[sky,fx]){c.width=Math.round(VW*DPR);c.height=Math.round(VH*DPR)}R.setPixelRatio(DPR);R.setSize(VW,VH,false);fit()}
const ray=new THREE.Raycaster(),ptr=new THREE.Vector2(),plane=new THREE.Plane(new THREE.Vector3(0,1,0),-TOP),hit=new THREE.Vector3();
function cellAt(e){if(!S.p||S.screen!=="game")return-1;ptr.set(e.clientX/VW*2-1,-(e.clientY/VH)*2+1);ray.setFromCamera(ptr,cam);if(!ray.ray.intersectPlane(plane,hit))return-1;const n=S.p.n,x=Math.round(hit.x+(n-1)/2),y=Math.round(hit.z+(n-1)/2);return x<0||y<0||x>=n||y>=n?-1:y*n+x}
function cellPage(k){const o=cellsO[k],a=scr(o.x,TOP+.5,o.z),b=scr(o.x+1,TOP+.5,o.z);return{x:a.x,y:a.y,cs:Math.abs(b.x-a.x)}}

// ---------- per-frame update ----------
const waves=[],beams=[],BEAM_A=new THREE.PlaneGeometry(1,.7),BEAM_B=new THREE.PlaneGeometry(.7,1);BEAM_A.userData.shared=BEAM_B.userData.shared=true;
function hop(x,z,t){let h=0;for(const w of waves){const d=Math.hypot(x-w.x,z-w.z);if(d>w.max)continue;const u=(t-w.t0)/1000*w.sp-d;if(u>0&&u<1)h+=w.amp*Math.sin(u*Math.PI)*(1-d/(w.max+2))}return h}
function addBeam(o,t){const n=S.p.n,mat=new THREE.MeshBasicMaterial({color:0xffe296,transparent:true,opacity:.5,blending:THREE.AdditiveBlending,depthWrite:false});
  const a=new THREE.Mesh(BEAM_A,mat);a.rotation.x=-Math.PI/2;a.position.set(0,TOP+.06,o.z);const b=new THREE.Mesh(BEAM_B,mat);b.rotation.x=-Math.PI/2;b.position.set(o.x,TOP+.065,0);board.add(a,b);beams.push({a,b,mat,t0:t,n})}
function update(t,dt){const game=S.screen==="game";
  while(waves.length&&t-waves[0].t0>4000)waves.shift();
  for(let i=beams.length-1;i>=0;i--){const b=beams[i],u=(t-b.t0)/520;if(u>=1){board.remove(b.a,b.b);b.mat.dispose();beams.splice(i,1);continue}if(u<0)continue;const e=1-(1-u)*(1-u);b.a.scale.x=b.n*e;b.b.scale.y=b.n*e;b.mat.opacity=.5*(1-u)}
  if(S.p&&cellsO.length){const n=S.p.n,{bad}=conflicts();
    cellsO.forEach((o,k)=>{const gx=k%n,gy=Math.floor(k/n),a=calm?1:clamp((t-S.introT-(gx+gy)*55)/420,0,1),e=a<1?Math.max(.001,back(a)):1,hv=calm?0:hop(o.x,o.z,t)*.34;
      o.tile.visible=a>0;o.tile.scale.setScalar(e);o.tile.position.y=.26+hv+(1-a)*(1-a)*2.2;const top=TOP+hv;
      if(o.mark){const u=clamp((t-(S.at[k]||0))/180,0,1);o.mark.scale.setScalar(calm?1:Math.max(.01,back(u)));o.mark.position.y=top+.02;o.mark.visible=a>=1}
      const isBad=bad.has(k);o.ring.visible=isBad&&S.cells[k]===2;if(o.ring.visible){o.ring.position.y=top+.03;o.ring.scale.setScalar(1+.06*Math.sin(t/120))}
      if(o.lan){const L=o.lan,U=L.userData,age=t-(S.at[k]||0),u=clamp(age/380,0,1),sc=calm?1:Math.max(.02,back(u)),sh=t-(S.shake[k]||-1e9);
        setBad(L,isBad&&!o.rise);
        if(o.rise){const r=(t-o.rise)/1000;if(r>0){L.position.y=top+.55+r*r*.28+r*.85;L.position.x=o.x+Math.sin(r*1.7+k)*.35*Math.min(1,r);L.rotation.z=Math.sin(r*2+k)*.12;U.li=Math.max(0,6-r*.8);U.gs.material.opacity=Math.max(0,.6-r*.04);if(L.position.y>26){drop(board,L);o.lan=null;o.rise=0}}}
        else{L.scale.setScalar(sc);L.position.set(o.x+(!calm&&sh<400?Math.sin(sh/22)*.09*(1-sh/400):0),top+.55+(calm?0:(1-u)*(1-u)*1.4+Math.sin(t/700+k)*.035),o.z);L.rotation.y=t/2600+k;L.rotation.z=calm?0:Math.sin(t/900+k)*.05;
          U.li=isBad?0:(4.4+(calm?0:.35*Math.sin(t/190+k)))*u;U.gs.material.opacity=isBad?.05:.62+(calm?0:.06*Math.sin(t/190+k))}}});
    let li=0;for(const o of cellsO)if(o.lan&&li<8){const l=LIGHTS[li++];l.position.copy(o.lan.position);l.intensity=o.lan.userData.li}for(;li<8;li++)LIGHTS[li].intensity=0;
    const hk=S.hintCell;hintRing.visible=hk>=0&&game;if(hintRing.visible){const o=cellsO[hk];hintRing.position.set(o.x,TOP+.12+.05*Math.sin(t/200),o.z);hintRing.scale.setScalar(1+.08*Math.sin(t/160));hintRing.material.opacity=.75+.25*Math.sin(t/160)}}
  // rocks
  if(game&&S.p&&!S.done&&!document.hidden){S.rockClock+=dt;if(S.rockClock>=S.rockEvery){S.rockClock=0;dropRock()}}
  rocks.forEach(m=>{const u=m.userData;if(!u.landed){u.vy-=26*dt;m.position.y+=u.vy*dt;if(m.position.y<=u.ty){m.position.y=u.ty;u.landed=true;u.sq=1;K.dipV-=1.6;trauma=Math.min(1,trauma+.22);
        const w=new THREE.Vector3();m.getWorldPosition(w);const p=scr(w.x,w.y,w.z);burst(p.x,p.y,7,"200,205,230",110);clip("lift",.8,.55)||tone(90,.2,"sine",.14);buzz(14);
        if(rocks.length>=MAXR&&!S.done)fail();else if(rocks.length>=MAXR-3)tone(72,.16,"sine",.12)}}
    else if(u.sq>0){u.sq=Math.max(0,u.sq-dt*5);m.scale.y=u.by*(1-.25*Math.sin(u.sq*Math.PI))}});
  for(let i=flying.length-1;i>=0;i--){const m=flying[i],u=m.userData;u.age+=dt;u.vy-=14*dt;m.position.x+=u.vx*dt;m.position.y+=u.vy*dt;m.position.z+=u.vz*dt;m.rotation.x+=u.sx*dt;m.rotation.z+=u.sz*dt;m.scale.multiplyScalar(1-dt*.9);if(u.age>1.5){scene.remove(m);flying.splice(i,1)}}
  // keeper body language
  const Lr=rocks.length/MAXR;Music.set(S.screen==="game"&&!S.done?Lr:0);K.dipV+=(-K.dip*60-K.dipV*9)*dt;K.dip+=K.dipV*dt;K.hopV-=11*dt;K.hop=Math.max(0,K.hop+K.hopV*dt);if(K.hop===0&&K.hopV<0)K.hopV=K.cheer>0?rnd(2.6,3.6):0;if(K.cheer>0)K.cheer-=dt;
  const sq=S.failed?.42:clamp(1-.26*Lr+K.dip*.5,.5,1.12),strain=clamp((Lr-.45)*2,0,1);
  KP.body.scale.set(1+(1-sq)*.45,sq,1+(1-sq)*.45);KP.body.position.set(calm?0:Math.sin(t/23)*.014*strain,.33+K.hop,0);
  KP.plank.position.set(0,.33+K.hop+1.6*sq,-.34);KP.plank.rotation.z=calm?0:Math.sin(t/31)*.02*strain+(K.cheer>0?Math.sin(t/90)*.08:0);
  KP.skin.color.setRGB(1,.85-.3*strain,.71-.36*strain);for(const e of KP.eyes)e.scale.y=S.failed?.2:strain>.5?.45:(Math.sin(t/1700)>.985?.1:1);
  KP.brows.forEach((e,i)=>{e.rotation.z=(i?-1:1)*(-.5*strain+(K.cheer>0?.25:0))});KP.mouth.rotation.z=K.cheer>0||(!strain&&!S.failed)?Math.PI:0;KP.hat.rotation.z=Math.sin(t/800)*.03+(K.cheer>0?Math.sin(t/110)*.2:0);
  KP.head.rotation.y=K.cheer>0?Math.sin(t/200)*.5:Math.sin(t/2100)*.25*(1-strain);
  // ambience
  flies.forEach(f=>{const u=f.userData;f.position.set(u.x+Math.sin(t/1000*u.sp+u.p)*1.2,u.y+Math.sin(t/700*u.sp+u.p*2)*.5,u.z+Math.cos(t/1300*u.sp+u.p)*1.2);f.material.opacity=.35+.6*Math.sin(t/400*u.sp+u.p)**2});
  farL.forEach(f=>{const u=f.userData;if(!calm)u.y+=u.v*dt;if(u.y>22)u.y=-5;f.position.set(u.x+Math.sin(t/3000+u.p)*1.5,u.y,u.z)});
  world.userData.ripples.forEach((r,i)=>{const u=((t/2600)+i/3)%1;r.scale.setScalar(.3+u*2.3);r.material.opacity=.4*(1-u)});
  world.userData.trees.forEach((g,i)=>{g.rotation.z=calm?0:Math.sin(t/1500+i)*.018});if(!calm)waterTex.offset.set(t/9000,Math.sin(t/4000)*.08);
  // camera: idle sway, home orbit, decaying trauma shake (visual only)
  trauma=Math.max(0,trauma-dt*1.4);zoomPulse=Math.max(0,zoomPulse-dt*.9);const s2=calm?0:trauma*trauma,ang=S.screen==="home"?Math.sin(t/5200)*.38:Math.sin(t/4100)*.035;
  const dx=camBase.x-camTarget.x,dz=camBase.z-camTarget.z,zz=1-.05*Math.sin(zoomPulse*Math.PI);
  cam.position.set(camTarget.x+(dx*Math.cos(ang)+dz*Math.sin(ang))*zz+s2*.22*Math.sin(t/14),camTarget.y+(camBase.y-camTarget.y)*zz+s2*.16*Math.sin(t/11),camTarget.z+(-dx*Math.sin(ang)+dz*Math.cos(ang))*zz);
  cam.lookAt(camTarget);cam.rotation.z+=s2*.012*Math.sin(t/17)}
let last=performance.now();
function frame(t){const dt=Math.min(.05,(t-last)/1000);last=t;drawSky(t);update(t,dt);R.render(scene,cam);drawFx(t,dt);requestAnimationFrame(frame)}

// ---------- UI ----------
function text(){document.documentElement.lang=S.lang;document.documentElement.dir=S.lang==="ar"?"rtl":"ltr";
  for(const k of["title","rules","play","daily","undo","hint","reset","auto","snd","load","fail","rotate","lang","blast","shop","shop2","close"])$("t-"+k).textContent=tr(k==="shop2"?"shop":k);
  $("next").textContent=tr("next");$("homeBtn").textContent=tr("home");$("retry").textContent=tr("retry");$("failInfo").textContent=tr("failInfo");$("langName").textContent=LANGS.find(l=>l[0]===S.lang)[1];for(const b of $("langList").children)b.setAttribute("aria-pressed",b.dataset.lang===S.lang);
  $("playSub").textContent=fmtN("levelN",load("level",1));const st=load("streak",0),done=load("dailyLast",0)===todayKey();
  $("dailySub").textContent=(done?tr("doneToday"):tr("newToday"))+(st>0?" · "+tr("streak")+" "+st:"");
  $("snd").setAttribute("aria-pressed",S.sound||S.music);$("t-snd2").textContent=tr("snd");$("sndClose").textContent=tr("close");for(const[id,k,v]of[["sfxT","sfx",S.sound],["musT","mus",S.music]]){$(id).textContent=tr(k)+" · "+tr(v?"on":"off");$(id).setAttribute("aria-pressed",v)}$("auto").setAttribute("aria-pressed",S.auto);$("hintN").textContent=S.hints+S.inv.hints;
  $("lvl").textContent=S.mode==="daily"?tr("daily"):fmtN("levelN",S.level);$("blastN").textContent=S.inv.blasts;shopText();fit()}
function pips(){if(!S.p)return;const n=S.p.n,{bad,count}=conflicts(),el=$("pips");if(el.children.length!==n)el.innerHTML="<i></i>".repeat(n);[...el.children].forEach((e,i)=>e.className=i<count?(bad.size?"bad":"on"):"");$("undo").disabled=!S.undo.length||S.done}
const say=m=>{$("msg").textContent=m};
function show(s){S.screen=s;document.body.dataset.screen=s;text()}
function clearRocks(){for(const m of rocks)KP.rocks.remove(m);for(const m of flying)scene.remove(m);rocks=[];flying=[];meter()}
function setPuzzle(p,cells){S.p=p;S.cells=cells;S.undo=[];S.at=[];S.shake=[];S.hintCell=-1;S.combo=0;S.maxCount=0;S.done=false;S.failed=false;S.rockClock=0;K.cheer=0;waves.length=0;S.introT=performance.now()+80;buildBoard();syncAll();fit()}
function demo(){const p=gradedPuzzle(5,77,1,5);const c=new Array(25).fill(0);p.sol.forEach((x,y)=>c[y*5+x]=2);S.demo=true;clearRocks();setPuzzle(p,c);for(let i=0;i<4;i++){dropRock();rocks[i].position.y=rocks[i].userData.ty;rocks[i].userData.landed=true}S.at=c.map(()=>-1e6)}

// ---------- actions ----------
function setCell(k,v,rec=true){if(S.done||S.cells[k]===v)return;const was=S.cells[k],now=performance.now();if(rec)S.undo.push([k,was]);S.cells[k]=v;S.at[k]=now;S.hintCell=-1;sync(k);
  const n=S.p.n,p=cellPage(k),o=cellsO[k];
  if(v===2){const{bad,count}=conflicts();
    if(bad.size){for(const b of bad)S.shake[b]=now;S.combo=0;trauma=Math.min(1,trauma+.4);sfx.bad();buzz([20,40,20])}
    else{S.combo++;const cb=Math.min(S.combo,6);sfx.place(count-1);buzz(10+cb*4);burst(p.x,p.y,12+cb*7,cb>=3?FW[(cb+1)%5]:"255,215,130",150+cb*25);
      rings.push({x:p.x,y:p.y,age:0,life:.5,r0:p.cs*.3,r1:p.cs*(1.4+cb*.25),rgb:"255,225,150"});waves.push({x:o.x,z:o.z,t0:now+140,sp:9,amp:.45+cb*.12,max:1.6+cb*.5});addBeam(o,now+60);trauma=Math.min(1,trauma+.12);
      if(count>S.maxCount){S.maxCount=count;if(count<n)blast(2+(S.combo>=3?1:0))}if($("msg").textContent===tr("how"))say("");
      if(S.combo>=2&&count<n){praise(p.x,p.y-p.cs*.5,tr("praise")[Math.min(S.combo-2,4)]);clip("hint",.35,1+S.combo*.08)}}
    if(S.auto)for(let j=0;j<n*n;j++)if(S.cells[j]===0&&j!==k&&blockedBy(j)){S.undo.push([j,0,1]);S.cells[j]=1;S.at[j]=now+120+Math.hypot(j%n-k%n,Math.floor(j/n)-Math.floor(k/n))*70;sync(j)}}
  else if(was===2){S.combo=0;sfx.lift();burst(p.x,p.y,6,"200,200,255",90)}else sfx.mark();
  pips();check()}
function check(){const n=S.p.n,{bad,count}=conflicts();if(count!==n||bad.size)return;S.done=true;clearInterval(S.tick);S.hintCell=-1;meter();
  const secs=Math.round((Date.now()-S.t0)/1000),got=S.used===0?3:S.used===1?2:1,key=S.mode==="daily"?"d"+todayKey():"l"+S.level,best=load("best."+key,null);
  if(best==null||secs<best)save("best."+key,secs);
  let info=tr("time")+" "+fmt(secs)+" · "+tr("best")+" "+fmt(Math.min(secs,best??secs));
  if(S.mode==="daily"){const lastD=load("dailyLast",0),st=load("streak",0),tk=todayKey();if(lastD!==tk){const y=new Date();y.setDate(y.getDate()-1);save("streak",lastD===dayKey(y)?st+1:1);save("dailyLast",tk)}
    info+=" · "+tr("streak")+" "+load("streak",1);$("next").style.display="none";say(tr("dailyDone"))}
  else{save("level",S.level+1);$("next").style.display="";say("")}
  [...$("stars").children].forEach((s,i)=>s.classList.toggle("got",i<got));$("winInfo").textContent=info;$("t-win").textContent=tr(got===3?"win3":got===2?"win2":"win");
  const now=performance.now(),sheetAt=calm?300:500+n*150+1100,run=S.run,live=()=>S.run===run&&S.done&&!S.failed;let i=0;
  cellsO.forEach((o,k)=>{if(S.cells[k]===2&&o.lan){o.rise=now+450+i*150;setTimeout(()=>{if(live())sfx.rise(k%8)},450+i*150);i++}});
  blast(rocks.length);K.cheer=6;K.hopV=3.4;zoomPulse=1;setTimeout(()=>{if(live())sfx.win()},350);buzz([30,60,30,60,60]);pips();
  if(!calm){flash();waves.push({x:0,z:0,t0:now+80,sp:7,amp:1.3,max:99});waves.push({x:0,z:0,t0:now+650,sp:7,amp:.75,max:99});
    setTimeout(()=>{if(live())praise(VW/2,VH*.36,tr(got===3?"win3":got===2?"win2":"win"),true)},250);
    for(let j=0;j<7;j++)setTimeout(()=>{if(live())firework(VW*(.15+Math.random()*.7),VH*(.1+Math.random()*.3),FW[j%5])},500+j*330+Math.random()*120);
    for(let j=0;j<got;j++)setTimeout(()=>{if(!live())return;const b=$("stars").children[j].getBoundingClientRect();burst(b.left+b.width/2,b.top+b.height/2,22,"255,215,120",220);rings.push({x:b.left+b.width/2,y:b.top+b.height/2,age:0,life:.45,r0:16,r1:70,rgb:"255,225,150"});clip("rise",.6,1+j*.2)||tone(SCALE[j*2+3],.3,"triangle",.12);buzz(18)},sheetAt+420+j*180)}
  setTimeout(()=>{if(live())$("win").classList.add("on")},sheetAt)}
function fail(){S.done=true;S.failed=true;clearInterval(S.tick);trauma=1;sfx.bad();buzz([60,40,120]);meter();
  const run=S.run;setTimeout(()=>{if(S.run===run&&S.failed)$("fail").classList.add("on")},calm?200:900)}
function start(same=false){S.run++;clearInterval(S.tick);$("win").classList.remove("on");$("fail").classList.remove("on");show("game");say(tr("gen"));S.demo=false;
  const run=S.run;setTimeout(()=>{if(S.run!==run)return;const p=same&&S.p?S.p:S.mode==="daily"?dailyPuzzle(todayKey()):levelPuzzle(S.level),n=p.n;clearRocks();
    setPuzzle(p,new Array(n*n).fill(0));S.hints=3;S.used=0;S.t0=Date.now();S.rockEvery=S.mode==="daily"?7:Math.max(5,9-S.level*.06);S.rockClock=S.rockEvery-4;
    S.tick=setInterval(()=>{$("time").textContent=fmt(Math.round((Date.now()-S.t0)/1000))},500);$("time").textContent="0:00";text();pips();meter();say(tr("how"));window.__lantern=S},30)}

// ---------- input ----------
let drag=null;
gl.addEventListener("pointerdown",e=>{const k=cellAt(e);if(k<0)return;drag={k,moved:false};gl.setPointerCapture(e.pointerId)});
gl.addEventListener("pointermove",e=>{if(!drag)return;const k=cellAt(e);if(k<0)return;if(k!==drag.k||drag.moved){if(!drag.moved){drag.moved=true;if(S.cells[drag.k]===0)setCell(drag.k,1)}if(S.cells[k]===0)setCell(k,1)}});
gl.addEventListener("pointerup",()=>{if(drag&&!drag.moved)setCell(drag.k,(S.cells[drag.k]+1)%3);drag=null});
gl.addEventListener("pointercancel",()=>{drag=null});
$("undo").onclick=()=>{if(S.done)return;sfx.tap();S.combo=0;let u=S.undo.pop();while(u){S.cells[u[0]]=u[1];S.at[u[0]]=performance.now();sync(u[0]);if(!u[2])break;u=S.undo.pop()}S.hintCell=-1;pips()};
$("reset").onclick=()=>{if(S.done&&!S.failed)return;sfx.tap();start(true)};
const saveInv=()=>{save("inv.hints",S.inv.hints);save("inv.blasts",S.inv.blasts)};
$("hint").onclick=()=>{if(S.done)return;if(S.hints<=0&&S.inv.hints<=0){say(tr("noHints"));openShop();return}const h=findHint();if(!h)return;sfx.hint();if(S.hints>0)S.hints--;else{S.inv.hints--;saveInv()}S.used++;if(h.why==="hGive")setCell(h.k,2);S.hintCell=h.k;say(tr(h.why));text()};
// rock blast: a paid item that clears every rock at once
$("blast").onclick=()=>{if(S.done||!S.p||S.screen!=="game")return;if(S.inv.blasts<=0){openShop();return}if(!rocks.length){sfx.tap();return}S.inv.blasts--;saveInv();trauma=Math.min(1,trauma+.5);blast(rocks.length);K.hopV=3.4;const b=$("blast").getBoundingClientRect();burst(b.left+b.width/2,b.top+20,18,"255,160,120",200);text()};

// ---------- shop ----------
// Purchases run in the native app (StoreKit through the Flutter frame). The page only asks and is told the result.
// Products are consumables: the items are added here, on the device, when the app reports a finished purchase.
const PRODUCTS={"com.noobclaw.lantern.hints10":{key:"buyHints",info:"buyHintsInfo",give:()=>{S.inv.hints+=10}},"com.noobclaw.lantern.blasts5":{key:"buyBlasts",info:"buyBlastsInfo",give:()=>{S.inv.blasts+=5}}};
const native=window.LanternNative&&typeof window.LanternNative.postMessage==="function"?window.LanternNative:null,prices={};let shopMsg="";
const toNative=o=>{try{native.postMessage(JSON.stringify(o))}catch(e){}};
function shopText(){const el=$("shopList");if(!el)return;el.innerHTML=Object.entries(PRODUCTS).map(([id,p])=>`<div class="item"><div><b>${tr(p.key)}</b><small>${tr(p.info)}</small><small class="own">${fmtN("owned",id.endsWith("hints10")?S.inv.hints:S.inv.blasts)}</small></div><button class="btn" data-id="${id}">${prices[id]||"…"}</button></div>`).join("");$("shopMsg").textContent=shopMsg||(native?"":tr("noStore"))}
function openShop(){sfx.tap();shopMsg="";shopText();$("shop").classList.add("on");if(native)toNative({type:"products",ids:Object.keys(PRODUCTS)})}
window.lanternStore={
  onProducts(list){for(const p of list||[])prices[p.id]=p.price;shopText()},
  onResult(r){const p=PRODUCTS[r&&r.id];if(r&&r.status==="ok"&&p){const seen=load("iap.done",[]);if(r.tx&&seen.includes(r.tx))return;p.give();saveInv();if(r.tx){seen.push(r.tx);save("iap.done",seen.slice(-50))}shopMsg=tr("bought");sfx.win();text()}else if(r&&r.status==="fail"){shopMsg=tr("buyFail");shopText()}else{shopMsg="";shopText()}}};
$("shopList").onclick=e=>{const b=e.target.closest("button[data-id]");if(!b)return;if(!native){shopMsg=tr("noStore");shopText();return}sfx.tap();shopMsg=tr("buying");shopText();toNative({type:"buy",id:b.dataset.id})};
$("shopClose").onclick=()=>{sfx.tap();$("shop").classList.remove("on")};$("shopChip").onclick=openShop;
if(native)toNative({type:"ready"});
$("next").onclick=()=>{S.level=load("level",S.level+1);start()};
$("retry").onclick=()=>{sfx.tap();start(true)};
$("homeBtn").onclick=$("back").onclick=()=>{S.run++;sfx.tap();clearInterval(S.tick);$("win").classList.remove("on");$("fail").classList.remove("on");S.level=load("level",S.level);S.screen="home";demo();show("home")};
$("play").onclick=()=>{sfx.tap();S.mode="levels";S.level=load("level",1);start()};
$("daily").onclick=()=>{sfx.tap();S.mode="daily";start()};
$("lang").onclick=()=>{sfx.tap();$("langSheet").classList.add("on")};
$("langSheet").onclick=e=>{const b=e.target.closest("button[data-lang]");if(b){S.lang=b.dataset.lang;save("lang",S.lang);text();if(S.screen==="game"&&$("msg").textContent)say(tr("how"))}$("langSheet").classList.remove("on")};
$("langList").innerHTML=LANGS.map(([c,n])=>`<button class="btn alt" data-lang="${c}" lang="${c}">${n}</button>`).join("");
Music.enable(S.music);Music.start();
$("snd").onclick=()=>{sfx.tap();$("sndSheet").classList.add("on")};
$("sfxT").onclick=()=>{S.sound=!S.sound;save("sound",S.sound);text();sfx.tap()};
$("musT").onclick=()=>{S.music=!S.music;save("music",S.music);Music.enable(S.music);text();sfx.tap()};
$("sndSheet").onclick=e=>{if(e.target===$("sndSheet")||e.target===$("sndClose"))$("sndSheet").classList.remove("on")};
$("auto").onclick=()=>{S.auto=!S.auto;save("auto",S.auto);text();sfx.tap()};
addEventListener("resize",layout);
window.__lanternApi={start,setCell,show,dropRock,cellPage,info:()=>({music:Music.state(),buffers:Object.keys(BUF).length,audio:AC?AC.state:"none",geo:R.info.memory.geometries,tex:R.info.memory.textures,programs:R.info.programs.length,rocks:rocks.length,lights:LIGHTS.length})};
layout();demo();text();requestAnimationFrame(frame);
