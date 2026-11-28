import { animate } from 'animejs';
let audio, master;
const pops=new Map(), transient=new Set(), timers=new Set();
export const motionAllowed=()=>localStorage.getItem('sorting-motion')!=='off'&&!matchMedia('(prefers-reduced-motion: reduce)').matches;
const later=(fn,ms)=>{const id=setTimeout(()=>{timers.delete(id);fn();},ms);timers.add(id);return id;};
function transientAnimation(node,options){
  const effect={node,animation:null};transient.add(effect);
  const done=options.onComplete;
  effect.animation=animate(node,{...options,onComplete:()=>{transient.delete(effect);node.remove();done?.();}});
  return effect;
}
export function cleanupFeedback(){
  for(const [node,effect] of pops){effect.animation?.cancel();node.style.transform=effect.rest;}
  pops.clear();
  for(const effect of transient){effect.animation?.cancel();effect.node.remove();}
  transient.clear();for(const id of timers)clearTimeout(id);timers.clear();
}
export function sound(kind,material='soft'){
  if(localStorage.getItem('sorting-sound')==='off')return;
  try{
    audio??=new AudioContext();if(audio.state==='suspended')audio.resume();
    if(!master){master=audio.createGain();master.gain.value=.55;master.connect(audio.destination);}
    const hard=/metal|glass/.test(material),notes=kind==='win'?[523,659,784,1047]:kind==='box'?[392,587,784]:kind==='blocked'?[185,155]:kind==='tool'?[440,880]:[kind==='pickup'?(hard?920:620):520];
    notes.forEach((frequency,index)=>{
      const at=audio.currentTime+index*.065,osc=audio.createOscillator(),gain=audio.createGain();
      osc.type=kind==='blocked'?'triangle':'sine';osc.frequency.setValueAtTime(frequency,at);
      osc.frequency.exponentialRampToValueAtTime(frequency*(kind==='pickup'?1.14:.96),at+.12);
      gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(kind==='tap'?.025:.065,at+.005);
      gain.gain.exponentialRampToValueAtTime(.0001,at+(hard?.22:.15));
      osc.connect(gain);gain.connect(master);osc.start(at);osc.stop(at+.24);
      osc.onended=()=>{osc.disconnect();gain.disconnect();};
    });
    if(kind==='box'){
      const size=Math.floor(audio.sampleRate*.09),buffer=audio.createBuffer(1,size,audio.sampleRate),data=buffer.getChannelData(0);
      for(let i=0;i<size;i++)data[i]=(Math.random()*2-1)*Math.exp(-i/(size*.15));
      const noise=audio.createBufferSource(),filter=audio.createBiquadFilter(),gain=audio.createGain();
      filter.type='lowpass';filter.frequency.value=700;gain.gain.value=.11;
      noise.buffer=buffer;noise.connect(filter);filter.connect(gain);gain.connect(master);noise.start();
      noise.onended=()=>{noise.disconnect();filter.disconnect();gain.disconnect();};
    }
  }catch{/* Optional presentation never prevents input or saving. */}
}
export function pop(node){
  if(!node||!motionAllowed())return;
  const previous=pops.get(node);previous?.animation.cancel();
  if(previous)node.style.transform=previous.rest;
  const effect={rest:node.style.transform,animation:null};pops.set(node,effect);
  effect.animation=animate(node,{scale:[1,.94,1.07,1],duration:280,ease:'out(3)',onComplete:()=>{
    if(pops.get(node)!==effect)return;node.style.transform=effect.rest;pops.delete(node);
  }});
}
function arrival(target){
  if(!target?.isConnected)return;
  pop(target);
  if(!motionAllowed())return;
  const r=target.getBoundingClientRect(),ring=document.createElement('i');
  ring.className='arrival-ring';ring.style.left=`${r.left+r.width/2}px`;ring.style.top=`${r.top+r.height/2}px`;
  ring.style.width=`${Math.min(r.width,r.height)*.85}px`;ring.style.height=ring.style.width;
  document.body.append(ring);
  transientAnimation(ring,{scale:[.5,1.55],opacity:[.9,0],duration:420,ease:'out(3)'});
}
export function fly(src,from,target){
  if(!from||!target)return;
  const key=target.dataset.feedbackKey;
  if(!motionAllowed()){arrival(target);return;}
  const to=target.getBoundingClientRect(),dx=to.left+to.width/2-from.x,dy=to.top+to.height/2-from.y;
  const image=document.createElement('img');image.className='flying-object';image.src=src;image.alt='';
  Object.assign(image.style,{left:`${from.x}px`,top:`${from.y}px`,width:`${from.size}px`,height:`${from.size}px`});
  document.body.append(image);
  // A short lift precedes the accelerated curve; destination always resolves to
  // the same logical bay/cell after the HUD has refreshed.
  transientAnimation(image,{x:[0,dx*.32,dx],y:[0,Math.min(-35,dy*.45-45),dy],scale:[1,1.13,.42],
    rotate:[-4,7,0],opacity:[1,1,0],duration:470,ease:'inOut(2)',onComplete:()=>arrival(document.querySelector(`[data-feedback-key="${key}"]`)??target)});
  for(let i=0;i<4;i++){
    const dot=document.createElement('i');dot.className='pickup-trail';
    dot.style.left=`${from.x}px`;dot.style.top=`${from.y}px`;document.body.append(dot);
    transientAnimation(dot,{x:[0,dx*.36,dx],y:[0,Math.min(-30,dy*.45-40)+i*4,dy],scale:[.7,1,0],opacity:[0,.8,0],delay:25+i*30,duration:400,ease:'inOut(2)'});
  }
}
export function finishBox(key){
  later(()=>{const target=document.querySelector(`[data-feedback-key="${key}"]`);if(!target)return;
    arrival(target);if(!motionAllowed())return;
    const r=target.getBoundingClientRect();
    for(let i=0;i<7;i++){
      const leaf=document.createElement('i');leaf.className='box-ribbon';leaf.style.background=['#e8bc65','#88b7a0','#e99679'][i%3];
      leaf.style.left=`${r.left+r.width/2}px`;leaf.style.top=`${r.top+r.height/2}px`;document.body.append(leaf);
      const angle=(i/7)*Math.PI*2;
      transientAnimation(leaf,{x:[0,Math.cos(angle)*42],y:[0,Math.sin(angle)*30-12,24],rotate:[0,100+i*30],opacity:[1,1,0],duration:600,ease:'out(2)'});
    }
  },440);
}
export function praise(host,label){
  if(!host?.isConnected)return;
  const r=host.getBoundingClientRect(),node=document.createElement('span');
  node.className='collection-praise';node.textContent=label;node.setAttribute('role','status');
  node.style.left=`${r.left+r.width/2}px`;node.style.top=`${r.top+48}px`;document.body.append(node);
  sound('box');
  if(!motionAllowed()){const effect={node,animation:null};transient.add(effect);later(()=>{transient.delete(effect);node.remove();},1000);return;}
  transientAnimation(node,{y:[8,-4,-12],scale:[.92,1.04,1],opacity:[0,1,1,0],duration:1100,ease:'out(3)'});
}
export function boardFeedback(host,kind){
  if(!host)return;
  host.dataset.feedback=kind;later(()=>{if(host.dataset.feedback===kind)delete host.dataset.feedback;},650);
}
export function celebrate(container){
  sound('win');if(!motionAllowed())return;
  container.querySelectorAll('.result-stars .glyph').forEach((star,index)=>animate(star,{scale:[0,1.22,1],rotate:[-18,6,0],opacity:[0,1],delay:140+index*150,duration:520,ease:'outBack'}));
  for(let i=0;i<30;i++){
    const piece=document.createElement('i');piece.className='confetti';piece.style.background=['#e8bc65','#88b7a0','#e99679','#fff4cb'][i%4];
    piece.style.left=`${8+(i*31)%84}%`;container.append(piece);
    transientAnimation(piece,{y:[-40,container.clientHeight+40],x:[0,(i%2?1:-1)*(18+i%40)],rotate:[0,300+i*11],opacity:[1,1,0],delay:(i%6)*65,duration:1200+(i%4)*180,ease:'in(1.4)'});
  }
}
document.addEventListener('click',event=>{
  const target=event.target.closest('button');if(target&&!target.disabled){pop(document.querySelector(`[data-feedback-key="${target.dataset.feedbackKey}"]`)??target);sound('tap');}
},{passive:true});
