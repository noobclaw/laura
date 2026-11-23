"use strict";
// Background music, synthesised live with Web Audio. No audio file is shipped.
// Three layers on one clock: a slow pad (chords), a plucked melody with echo, and a low pulse that
// only comes in when rocks pile up. `Music.set(x)` takes the load 0..1 and moves tempo, brightness
// and the pulse with it, so the music itself tells the player how close the keeper is to falling.
// Uses the shared AudioContext `AC` from core.js, which is created inside the first touch (iOS rule).
const Music=(()=>{
  const D=146.83, st=n=>D*Math.pow(2,n/12);
  const PENTA=[0,3,5,7,10,12,15,17,19,22];             // D minor pentatonic over two octaves
  const CHORDS=[[-12,7,15],[-16,3,12],[-9,7,12],[-14,5,10]]; // D, Bb, F, C roots with pentatonic tops
  let on=true, out=null, wet=null, padLP=null, timer=0, nextT=0, step=0, load=0, cur=0, deg=4, seed=7, phrase=[];
  const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};
  function graph(){
    if(out||!AC)return;
    out=AC.createGain();out.gain.value=0;out.connect(AC.destination);
    const dl=AC.createDelay(1.5),fb=AC.createGain(),lp=AC.createBiquadFilter();
    dl.delayTime.value=.42;fb.gain.value=.36;lp.type="lowpass";lp.frequency.value=1800;
    wet=AC.createGain();wet.gain.value=.5;wet.connect(dl);dl.connect(lp);lp.connect(fb);fb.connect(dl);lp.connect(out);
    padLP=AC.createBiquadFilter();padLP.type="lowpass";padLP.frequency.value=700;padLP.Q.value=.4;padLP.connect(out);
  }
  function env(g,t,a,peak,d){g.gain.setValueAtTime(.0001,t);g.gain.linearRampToValueAtTime(peak,t+a);g.gain.exponentialRampToValueAtTime(.0001,t+a+d)}
  function pluck(f,t,vol){
    const o=AC.createOscillator(),o2=AC.createOscillator(),g=AC.createGain(),g2=AC.createGain();
    o.type="triangle";o.frequency.value=f;o2.type="sine";o2.frequency.value=f*2.005;g2.gain.value=.28;
    env(g,t,.006,vol,1.5);o.connect(g);o2.connect(g2).connect(g);g.connect(out);g.connect(wet);
    o.start(t);o2.start(t);o.stop(t+1.7);o2.stop(t+1.7);
  }
  function pad(notes,t,len){
    for(const n of notes)for(const det of[-5,6]){
      const o=AC.createOscillator(),g=AC.createGain();o.type="sawtooth";o.frequency.value=st(n);o.detune.value=det;
      g.gain.setValueAtTime(.0001,t);g.gain.linearRampToValueAtTime(.028,t+len*.35);g.gain.linearRampToValueAtTime(.0001,t+len*1.15);
      o.connect(g).connect(padLP);o.start(t);o.stop(t+len*1.2);
    }
  }
  function thump(t,vol){
    const o=AC.createOscillator(),g=AC.createGain();o.type="sine";o.frequency.setValueAtTime(110,t);o.frequency.exponentialRampToValueAtTime(52,t+.16);
    env(g,t,.004,vol,.3);o.connect(g).connect(out);o.start(t);o.stop(t+.4);
  }
  function newPhrase(){phrase=[];for(let i=0;i<8;i++){const rest=rnd()<(i%2?.55:.2);if(!rest)deg=Math.max(1,Math.min(PENTA.length-2,deg+[-2,-1,-1,1,1,2][rnd()*6|0]));phrase.push(rest?-1:deg)}}
  function tick(){
    if(!on||!AC||AC.state!=="running")return;graph();
    const now=AC.currentTime;if(nextT<now)nextT=now+.06;
    cur+=(load-cur)*.12;                                   // ease toward the target so changes are never abrupt
    out.gain.setTargetAtTime(.55,now,.6);padLP.frequency.setTargetAtTime(700+cur*1500,now,.5);
    while(nextT<now+.35){
      const bpm=72+cur*30,e=30/bpm,s=step%32;              // e = one eighth note
      if(s%8===0){if(s===0||rnd()<.5)newPhrase();}
      if(s===0||s===16){const c=CHORDS[(step/16|0)%4];pad(c,nextT,e*16);pluck(st(c[0]+12),nextT,.05)}
      const d=phrase[s%8];
      if(d>=0){let n=PENTA[d];if(cur>.7&&rnd()<.3)n+=1;    // a half-step rub when things are tight
        pluck(st(n+12),nextT,.085+.03*rnd())}
      if(cur>.45){const v=(cur-.45)*.5;if(s%4===0)thump(nextT,v);else if(cur>.8&&s%2===0)thump(nextT,v*.5)}
      nextT+=e;step++;
    }
  }
  return{
    start(){if(!timer)timer=setInterval(tick,110)},
    set(x){load=Math.max(0,Math.min(1,x||0))},
    enable(v){on=!!v;if(!on&&out&&AC)out.gain.setTargetAtTime(0,AC.currentTime,.15)},
    state:()=>({on,steps:step,graph:!!out,load:+cur.toFixed(2)})
  };
})();
// The music must stop when the app goes to the background and come back with it.
document.addEventListener("visibilitychange",()=>{try{if(!AC)return;if(document.hidden)AC.suspend();else AC.resume()}catch(e){}});
