import { frameFor,viewTransform,worldToScreen,screenToWorld } from '../src/view.js';
import { resolvePose } from '../src/poses.js';
import React, { Suspense, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { OrthographicCamera } from '@react-three/drei/core/OrthographicCamera.js';
import { RoundedBox } from '@react-three/drei/core/RoundedBox.js';
import { Line } from '@react-three/drei/core/Line.js';
import { Physics, RigidBody, CuboidCollider, BallCollider, CylinderCollider } from '@react-three/rapier';
import { Texture, SRGBColorSpace, Vector4, Matrix4, MeshBasicMaterial, DataTexture, RGBAFormat, AdditiveBlending, NoToneMapping, PCFShadowMap, LinearFilter, MirroredRepeatWrapping, ClampToEdgeWrapping } from 'three';
import { EffectComposer, RenderPass, EffectPass, BloomEffect } from 'postprocessing';
import { BatchedRenderer, ParticleSystem, ConstantValue, IntervalValue, ConstantColor, SphereEmitter, RenderMode } from 'three.quarks';

const motionAllowed = () => localStorage.getItem('sorting-motion') !== 'off' && !matchMedia('(prefers-reduced-motion: reduce)').matches;
const recoveryWords = () => ({ 'zh-CN': ['画面暂时中断，已保存的进度仍在。','重新载入'], 'zh-TW': ['畫面暫時中斷，已儲存的進度仍在。','重新載入'] })[document.documentElement.lang]
  ?? ['The graphics were interrupted. Your saved progress is safe.','Reload'];
function GraphicsRecovery({ bridge }) {
  useEffect(() => { bridge.host.dataset.graphics = 'lost'; return () => { delete bridge.host.dataset.graphics; }; }, [bridge]);
  const words = recoveryWords();
  return <div className="graphics-recovery" role="alert"><p>{words[0]}</p><button type="button" onClick={() => location.reload()}>{words[1]}</button></div>;
}
class GraphicsGuard extends React.Component {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() { return this.state.failed ? <GraphicsRecovery bridge={this.props.bridge} /> : this.props.children; }
}
function sparkTexture() {
  const pixels = new Uint8Array(32 * 32 * 4);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    const dx=Math.abs(x-15.5)/16,dy=Math.abs(y-15.5)/16;
    const d = Math.min(Math.hypot(dx,dy),Math.pow(dx,.55)+Math.pow(dy,.55)), i = (y * 32 + x) * 4;
    pixels[i] = pixels[i + 1] = pixels[i + 2] = 255;
    const ray=Math.max(0,1-Math.min(dx*8+dy,dy*8+dx));
    pixels[i + 3] = Math.round(Math.min(1,Math.max(0,1-d)**3+ray*.55)*255);
  }
  const texture = new DataTexture(pixels, 32, 32, RGBAFormat); texture.needsUpdate = true;
  return texture;
}
function Pipeline({ bridge }) {
  const { gl, scene, camera, size } = useThree();
  const composer = useMemo(() => {
    const value = new EffectComposer(gl, { multisampling: 0 });
    value.addPass(new RenderPass(scene, camera));
    if(!bridge.board)value.addPass(new EffectPass(camera, new BloomEffect({ intensity: .12, luminanceThreshold: .92, luminanceSmoothing: .18, mipmapBlur: false })));
    return value;
  }, [gl, scene, camera]);
  useEffect(() => { composer.setSize(size.width, size.height); }, [composer, size]);
  useEffect(() => () => composer.dispose(), [composer]);
  const measurements = useRef({ seconds: 0, frames: 0, time: performance.now() });
  useFrame((_, dt) => {
    if (document.hidden || bridge.host.dataset.graphics === 'lost') return;
    gl.info.reset();composer.render(Math.min(dt, .05));
    const meter = measurements.current;
    meter.seconds += dt; meter.frames++;
    if (meter.seconds >= 1) {
      bridge.metrics = { fps: Math.round(meter.frames / meter.seconds), calls: gl.info.render.calls,
        textures: gl.info.memory.textures, geometries: gl.info.memory.geometries,
        pixelRatio: gl.getPixelRatio(), buffer: [gl.domElement.width,gl.domElement.height], postBuffer: [composer.inputBuffer.width,composer.inputBuffer.height],
        particles: bridge.particleCount ?? 0, bodies: bridge.bodies ?? 0 };
      bridge.host.dataset.renderStats = JSON.stringify(bridge.metrics);
      meter.frames = 0; meter.seconds = 0;
    }
  }, 1);
  return null;
}
function Sparks({ bridge, unit = 1 }) {
  const { scene } = useThree();
  const resource = useMemo(() => ({ renderer: new BatchedRenderer(), texture: sparkTexture(), effects: [] }), []);
  useEffect(() => {
    scene.add(resource.renderer);
    return () => {
      resource.effects.forEach(({ system, material }) => { resource.renderer.deleteSystem(system); system.dispose(); material.dispose(); });
      resource.renderer.batches.forEach(batch => { batch.geometry?.dispose(); batch.material?.dispose(); });
      resource.texture.dispose(); scene.remove(resource.renderer);
    };
  }, [scene, resource]);
  useFrame((_, delta) => {
    if (document.hidden) return;
    const dt = Math.min(delta, .05), queue = bridge.sparks.splice(0);
    if (motionAllowed()) for (const event of queue.slice(-4)) {
      if (resource.effects.length >= 10) break;
      const count = event.large ? 24 : 9;
      const material = new MeshBasicMaterial({ map: resource.texture, transparent: true, depthWrite: false, blending: AdditiveBlending, toneMapped: false });
      const system = new ParticleSystem({ duration: .1, looping: false, autoDestroy: false,
        startLife: new IntervalValue(.28, .65), startSpeed: new IntervalValue(65 * unit, 150 * unit),
        startSize: new IntervalValue(9 * unit, 23 * unit), startColor: new ConstantColor(new Vector4(1, .76, .22, 1)),
        emissionOverTime: new ConstantValue(0), emissionBursts: [{ time: 0, count: new ConstantValue(count), cycle: 1, interval: .01, probability: 1 }],
        shape: new SphereEmitter({ radius: 5 * unit }), material, renderMode: RenderMode.BillBoard, worldSpace: true,
      });
      system.emitter.position.set(event.x, event.y, 20 * unit);
      scene.add(system.emitter); resource.renderer.addSystem(system); system.play();
      resource.effects.push({ system, material, age: 0, count });bridge.host.dataset.effectsCreated=String(Number(bridge.host.dataset.effectsCreated??0)+1);
    }
    resource.renderer.update(dt);
    resource.effects = resource.effects.filter(effect => {
      effect.age += dt;
      if (effect.age < .9) return true;
      resource.renderer.deleteSystem(effect.system); scene.remove(effect.system.emitter); effect.system.dispose(); effect.material.dispose();
      return false;
    });
    bridge.host.dataset.activeEffects=String(resource.effects.length);
    bridge.particleCount = resource.effects.reduce((sum, effect) => sum + effect.count, 0);
  });
  return null;
}
function PicturePlane({ texture, extent, position = [0, 0, 0], stretch = [1, 1], heading = 0, order = 0 }) {
  return <mesh position={position} rotation={[0, 0, heading * Math.PI / 180]} scale={[stretch[0], stretch[1], 1]} renderOrder={order}>
    <planeGeometry args={extent} />
    <meshBasicMaterial map={texture} transparent depthWrite={false} toneMapped={false} />
  </mesh>;
}
function ContactShadows({payload,ids}) {
  const mesh=useRef();
  const texture=useMemo(()=>{
    const pixels=new Uint8Array(64*64*4);
    for(let y=0;y<64;y++)for(let x=0;x<64;x++){
      const radius=Math.hypot((x-31.5)/31.5,(y-31.5)/31.5),i=(y*64+x)*4;
      pixels[i]=53;pixels[i+1]=43;pixels[i+2]=31;pixels[i+3]=Math.round(Math.max(0,1-radius)**1.7*65);
    }
    const map=new DataTexture(pixels,64,64,RGBAFormat);map.needsUpdate=true;return map;
  },[]);
  useEffect(()=>()=>texture.dispose(),[texture]);
  useLayoutEffect(()=>{
    if(!mesh.current)return;
    ids.forEach((id,index)=>{
      const raw=payload.stage.specimens[id],token=resolvePose(raw,payload.forms[raw.form],id),extent=payload.forms[token.form].extent;
      const matrix=new Matrix4().makeRotationZ(token.heading*Math.PI/180);
      const scale=new Matrix4().makeScale(extent[0]*Math.abs(token.stretch[0])*.92,extent[1]*Math.abs(token.stretch[1])*.73,1);
      matrix.multiply(scale);matrix.setPosition(token.at[0]+3,token.at[1]-7,-.5);
      mesh.current.setMatrixAt(index,matrix);
    });
    mesh.current.count=ids.length;mesh.current.instanceMatrix.needsUpdate=true;
  },[ids,payload]);
  return <instancedMesh ref={mesh} args={[null,null,payload.stage.specimens.length]} renderOrder={-.5} frustumCulled={false}>
    <planeGeometry args={[1,1]}/><meshBasicMaterial map={texture} transparent depthWrite={false} toneMapped={false}/>
  </instancedMesh>;
}
function RoomBackdrop({ texture, extent: [width, height] }) {
  const room = useRef();
  useFrame(({ camera, size }) => {
    if (!room.current) return;
    // Fit a single room across the visible width. Repeating the entire room
    // duplicates furniture; only FloorContinuation may tile its empty floor band.
    const visibleRight = Math.abs(camera.position.x) + size.width / (2 * camera.zoom);
    const top = Math.max(height / 2, camera.position.y + size.height / (2 * camera.zoom));
    const extraHeight = top - height / 2;
    room.current.scale.set(Math.max(1, visibleRight * 2 / width), 1 + extraHeight / height, 1);
    room.current.position.y = extraHeight / 2;
  });
  return <group ref={room}>
    <FloorContinuation texture={texture} extent={[width, height]} />
    <PicturePlane texture={texture} extent={[width, height]} position={[0, 0, -2]} order={-1} />
  </group>;
}
function FloorContinuation({ texture, extent: [width, height] }) {
  // Extend only the lowest floor band of the room image. The room and specimens
  // retain their shared world coordinates, including during camera zoom/pan.
  const strips = useMemo(() => [0, 1].map(direction => {
    const tile = texture.clone();
    tile.wrapS = MirroredRepeatWrapping;
    tile.repeat.set(7, direction ? .04 : -.04);
    tile.offset.set(-3, direction ? 0 : .04);
    tile.needsUpdate = true;
    return tile;
  }), [texture]);
  useEffect(() => () => strips.forEach(tile => tile.dispose()), [strips]);
  const planes = useRef();
  useFrame(({ camera, size }) => {
    if (!planes.current) return;
    const halfView = size.height / (2 * camera.zoom), halfStrip = height * .02;
    for (const mesh of planes.current.children) mesh.visible = mesh.position.y + halfStrip >= camera.position.y - halfView && mesh.position.y - halfStrip <= camera.position.y + halfView;
  });
  return <group ref={planes}>{Array.from({ length: 64 }, (_, index) => <PicturePlane key={index}
    texture={strips[index % 2]} extent={[width * 7, height * .04]}
    position={[0, -height / 2 - (index + .5) * height * .04, -3]} order={-2} />)}</group>;
}
function BoardWorld({ bridge, payload, pictures, state, focusToken }) {
  const { camera, size } = useThree();
  const textures = useMemo(() => new Map([...pictures].map(([path, image]) => {
    const texture = new Texture(image); texture.generateMipmaps=false;texture.minFilter=LinearFilter;texture.magFilter=LinearFilter;texture.wrapS=ClampToEdgeWrapping;texture.wrapT=ClampToEdgeWrapping;texture.colorSpace = SRGBColorSpace; texture.needsUpdate = true;
    return [path, texture];
  })), [pictures]);
  useEffect(() => () => textures.forEach(texture => texture.dispose()), [textures]);
  useEffect(() => {
    const view=viewTransform(bridge.frame,size.width,size.height,bridge.magnification,bridge.pan);camera.zoom=view.zoom;camera.position.set(...view.center,2000);camera.updateProjectionMatrix();bridge.zoom=view.zoom;
  }, [camera, size, payload, bridge]);
  useFrame(()=>{const view=viewTransform(bridge.frame,size.width,size.height,bridge.magnification,bridge.pan);camera.zoom=view.zoom;camera.position.set(...view.center,2000);camera.updateProjectionMatrix();});
  return <>
    <RoomBackdrop texture={textures.get(payload.scene.background)} extent={payload.scene.extent} />
    <ContactShadows payload={payload} ids={state.board}/>
    {state.board.map(id => {
      const raw=payload.stage.specimens[id],form=payload.forms[raw.form],token=resolvePose(raw,form,id);
      const marked = state.promptToken === id || state.scanTokens.includes(id) || focusToken === id;
      return <group key={id}>
        <PicturePlane texture={textures.get(payload.scene.sprites[token.form])} extent={form.extent} position={[...token.at, id * .01]} stretch={token.stretch} heading={token.heading} order={id} />
        {marked && <group position={[...token.at, 8]} rotation={[0, 0, token.heading * Math.PI / 180]} scale={[...token.stretch, 1]}>
          <Line points={[...form.outline, form.outline[0]].map(([x,y]) => [x,y,0])} color={focusToken === id ? '#fff8d4' : '#ffe164'} lineWidth={3} depthTest={false} />
        </group>}
      </group>;
    })}
    <Sparks bridge={bridge} />
    <Pipeline bridge={bridge} />
  </>;
}
function Toy({ at, color, bridge, index }) {
  const body = useRef(), seen = useRef(bridge.toss);
  useFrame(() => {
    if(!body.current)return;
    const p=body.current.translation();if(p.y<-5||Math.abs(p.x)>4||Math.abs(p.z)>4){body.current.setTranslation({x:at[0],y:at[1],z:at[2]},true);body.current.setLinvel({x:0,y:0,z:0},true);}
    if(seen.current===bridge.toss)return;
    seen.current = bridge.toss;
    if (!motionAllowed()) return;
    body.current.applyImpulse({ x: (index % 2 ? 1 : -1) * .6, y: 1.6 + index * .1, z: (index % 3 - 1) * .3 }, true);
    body.current.applyTorqueImpulse({ x: .12, y: .18, z: .08 }, true);
  });
  const type=index%3;
  const hit=event=>{event.stopPropagation();};
  return <RigidBody ref={body} position={at} colliders={false} restitution={type===1?.52:.18} friction={type===2?.42:.78} linearDamping={.35} angularDamping={.5}>
    {type===0&&<><CuboidCollider args={[.325,.325,.325]} mass={.18}/><RoundedBox args={[.65,.65,.65]} radius={.08} smoothness={3} castShadow receiveShadow onPointerDown={hit}><meshStandardMaterial color="#d7ad71" roughness={.82}/></RoundedBox></>}
    {type===1&&<><BallCollider args={[.34]} mass={.12}/><mesh castShadow receiveShadow onPointerDown={hit}><sphereGeometry args={[.34,24,16]}/><meshStandardMaterial color={color} roughness={.68}/></mesh></>}
    {type===2&&<><CylinderCollider args={[.35,.26]} mass={.3}/><mesh castShadow receiveShadow onPointerDown={hit}><cylinderGeometry args={[.26,.26,.7,24]}/><meshStandardMaterial color="#d5e1df" roughness={.28} metalness={.7}/></mesh></>}
  </RigidBody>;
}
function PackingWorld({ bridge }) {
  const { size } = useThree();
  const toyPositions = motionAllowed() ? [[.1,.8,0],[-.65,.7,.15],[.65,1.5,-.3],[0,2.0,.3],[-.55,2.6,-.3],[.55,3.0,.2]]
    : [[-.7,-.55,-.25],[0,-.55,-.25],[.7,-.55,-.25],[-.7,.12,.15],[0,.12,.15],[.7,.12,.15]];
  const [hidden,setHidden]=useState(document.hidden);
  useEffect(()=>{const change=()=>setHidden(document.hidden);document.addEventListener('visibilitychange',change);return()=>document.removeEventListener('visibilitychange',change);},[]);
  useEffect(() => { bridge.bodies = 7; return () => { bridge.bodies = 0; }; }, [bridge]);
  return <>
    <OrthographicCamera makeDefault position={[4, 3, 8]} zoom={size.width / 6.4} near={.1} far={100} onUpdate={camera => camera.lookAt(0, 0, 0)} />
    <ambientLight intensity={1.8} />
    <directionalLight position={[-3,6,5]} intensity={3.2} color="#fff1cf" castShadow shadow-mapSize={[512,512]} shadow-bias={-.001} />
    <mesh rotation={[-Math.PI/2,0,0]} position={[0,-1.16,0]} receiveShadow><planeGeometry args={[9,9]}/><shadowMaterial transparent opacity={.2}/></mesh>
    <Suspense fallback={null}>
      <Physics gravity={[0,-7,0]} timeStep={1/60} paused={hidden||!motionAllowed()} colliders={false}>
        <RigidBody type="fixed" position={[0,-1,0]} colliders={false}>
          <CuboidCollider args={[1.4,.12,1]} />
          <RoundedBox args={[2.8,.24,2]} radius={.08} smoothness={3}><meshStandardMaterial color="#b97531" /></RoundedBox>
          {[[0,.45,-1.03],[0,.45,1.03]].map((at,i) => <group key={i} position={at}>
            <CuboidCollider args={[1.45,.55,.10]} /><RoundedBox args={[2.9,1.1,.20]} radius={.05} smoothness={2}><meshStandardMaterial color={i ? '#d7994a' : '#e0b16d'} /></RoundedBox>
          </group>)}
          {[[-1.42,.45,0],[1.42,.45,0]].map((at,i) => <group key={i} position={at}>
            <CuboidCollider args={[.10,.55,1.05]} /><RoundedBox args={[.2,1.1,2.1]} radius={.04} smoothness={2}><meshStandardMaterial color="#ce964f" /></RoundedBox>
          </group>)}
        </RigidBody>
        {toyPositions.map((at,index) => <Toy key={index} index={index} at={at} color={['#6ec7b5','#f4927e','#ffd36a'][index%3]} bridge={bridge} />)}
      </Physics>
    </Suspense>
    <Sparks bridge={bridge} unit={.01} /><Pipeline bridge={bridge} />
  </>;
}
function canvasProps(host, bridge) {
  return { shadows: bridge.board ? false : {type:PCFShadowMap}, dpr: bridge.board ? [2, 2] : [1, 1.5], gl: { antialias: true, alpha: true, powerPreference: 'high-performance' },
    fallback: <div className="graphics-fallback">{recoveryWords()[0]}</div>,
    onCreated: ({ gl }) => {
      gl.info.autoReset=false;gl.outputColorSpace = SRGBColorSpace; gl.toneMapping = NoToneMapping; gl.setClearColor('#000000', 0);
      host.dataset.renderer = 'three.js'; host.dataset.presentation = 'r3f+rapier+quarks+postprocessing';
      bridge.canvas = gl.domElement;
      let recovery;
      const restored = () => { recovery?.remove(); recovery = null; delete host.dataset.graphics; };
      const lost = event => {
        event.preventDefault(); host.dataset.graphics = 'lost';
        if (recovery) return;
        const words = recoveryWords();
        recovery = document.createElement('div'); recovery.className = 'graphics-recovery'; recovery.setAttribute('role','alert');
        const text = document.createElement('p'); text.textContent = words[0];
        const button = document.createElement('button'); button.type = 'button'; button.textContent = words[1];
        button.onclick = () => location.reload(); recovery.append(text, button); host.append(recovery);
      };
      gl.domElement.addEventListener('webglcontextlost', lost);
      gl.domElement.addEventListener('webglcontextrestored', restored);
      bridge.cleanupGraphics = () => { gl.domElement.removeEventListener('webglcontextlost', lost); gl.domElement.removeEventListener('webglcontextrestored', restored); restored(); };
    },
  };
}
export function attachPacking(host,{onToss}={}) {
  const root = createRoot(host), bridge = { host, sparks: [], toss: 0 };
  root.render(<GraphicsGuard bridge={bridge}><Canvas {...canvasProps(host, bridge)}><PackingWorld bridge={bridge} /></Canvas></GraphicsGuard>);
  const words=({'zh-CN':'轻点让玩具弹起来','zh-TW':'輕點讓玩具彈起來'})[document.documentElement.lang]??'Tap to bounce the toys';
  host.setAttribute('aria-label',words);host.setAttribute('role','button');host.tabIndex=0;
  const toss=()=>{bridge.toss++;host.dataset.tosses=String(bridge.toss);bridge.sparks.push({x:0,y:.8,large:true});onToss?.();};
  const key=event=>{if(!['Enter',' '].includes(event.key))return;event.preventDefault();toss();};
  host.addEventListener('click',toss);host.addEventListener('keydown',key);
  return { dispose: () => { host.removeEventListener('click',toss);host.removeEventListener('keydown',key);bridge.cleanupGraphics?.(); root.unmount(); }, metrics: () => bridge.metrics };
}
export function attachThreeBoard(host, { payload, pictures, currentRound, onPick, label }) {
  const root = createRoot(host), bridge = { host, sparks: [], zoom: 1, board: true,frame:frameFor(payload),magnification:1,pan:[0,0] };
  let focusToken = null;
  const props=canvasProps(host,bridge),camera={position:[0,0,2000],zoom:1,near:.1,far:5000};
  const project = tokenId => {
    const raw = payload.stage.specimens[tokenId]; if (!raw) return null;
    const token=resolvePose(raw,payload.forms[raw.form],tokenId);
    const bounds = host.getBoundingClientRect();
    const view=viewTransform(bridge.frame,bounds.width,bounds.height,bridge.magnification,bridge.pan),zoom=view.zoom;
    const [x,y]=worldToScreen(token.at,view,bounds.width,bounds.height);
    const form = payload.forms[token.form];
    return { x: bounds.left+x, y: bounds.top+y,
      size: Math.max(24, Math.min(86, Math.max(...form.extent)*Math.abs(token.stretch[0])*zoom)) };
  };
  function draw() {
    const round = currentRound(); if (!round || !host.isConnected) return;
    root.render(<GraphicsGuard bridge={bridge}><Canvas {...props} orthographic camera={camera}>
      <BoardWorld bridge={bridge} payload={payload} pictures={pictures} state={round.inspect()} focusToken={focusToken} />
    </Canvas></GraphicsGuard>);
  }
  let drag;
  const down=event=>{if(event.button!==0||event.target.closest?.('.graphics-recovery'))return;const r=host.getBoundingClientRect(),v=viewTransform(bridge.frame,r.width,r.height,bridge.magnification,bridge.pan);bridge.pan=v.center.map((x,i)=>x-bridge.frame.center[i]);drag={x:event.clientX,y:event.clientY,lastX:event.clientX,lastY:event.clientY,moved:false};host.setPointerCapture(event.pointerId);};
  const move=event=>{if(!drag||bridge.magnification===1)return;const dx=event.clientX-drag.x,dy=event.clientY-drag.y;if(Math.hypot(dx,dy)>6)drag.moved=true;if(!drag.moved)return;const r=host.getBoundingClientRect(),v=viewTransform(bridge.frame,r.width,r.height,bridge.magnification,bridge.pan);const pan=[bridge.pan[0]-(event.clientX-drag.lastX)/v.zoom,bridge.pan[1]+(event.clientY-drag.lastY)/v.zoom];const bounded=viewTransform(bridge.frame,r.width,r.height,bridge.magnification,pan);bridge.pan=bounded.center.map((x,i)=>x-bridge.frame.center[i]);drag.lastX=event.clientX;drag.lastY=event.clientY;};
  const pointer=event=>{if(!drag)return;const moved=drag.moved;drag=null;if(moved)return;
    const rect=host.getBoundingClientRect(),v=viewTransform(bridge.frame,rect.width,rect.height,bridge.magnification,bridge.pan);
    onPick(screenToWorld([event.clientX-rect.left,event.clientY-rect.top],v,rect.width,rect.height),12/v.zoom);
  };
  const cancel=()=>{drag=null;};
  const keyboard = event => {
    if (event.target.closest?.('.graphics-recovery')) return;
    const round = currentRound();
    if (!round || !['ArrowRight','ArrowLeft','ArrowUp','ArrowDown','Enter',' '].includes(event.key)) return;
    event.preventDefault();
    const choices = round.inspect().board.filter(id => !round.isObstructed(id)); if (!choices.length) return;
    if (['Enter',' '].includes(event.key)) { const id = choices.includes(focusToken) ? focusToken : choices[0]; onPick(round.tokenInfo(id).at,0,id); }
    else { const step = ['ArrowLeft','ArrowUp'].includes(event.key) ? -1 : 1, index = choices.indexOf(focusToken);
      focusToken = choices[index<0 ? (step>0?0:choices.length-1) : (index+step+choices.length)%choices.length];
      host.setAttribute('aria-label',`${label} · ${choices.indexOf(focusToken)+1}/${choices.length}`); }
    draw();
  };
  host.addEventListener('pointerdown',down);host.addEventListener('pointermove',move);host.addEventListener('pointerup',pointer);host.addEventListener('pointercancel',cancel);host.addEventListener('keydown',keyboard);
  draw();
  return { draw, project, metrics: () => bridge.metrics,
    toggleZoom:()=>{bridge.magnification=bridge.magnification===1?1.6:1;bridge.pan=[0,0];host.dataset.magnification=bridge.magnification;return bridge.magnification;},
    burst: (tokenId,large=false) => { const token=payload.stage.specimens[tokenId];const at=token&&resolvePose(token,payload.forms[token.form],tokenId).at;if(at)bridge.sparks.push({x:at[0],y:at[1],large}); },
    dispose: () => { host.removeEventListener('pointerdown',down);host.removeEventListener('pointermove',move);host.removeEventListener('pointerup',pointer);host.removeEventListener('pointercancel',cancel);host.removeEventListener('keydown',keyboard);bridge.cleanupGraphics?.();root.unmount(); }
  };
}
