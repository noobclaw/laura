// Scene switch: one button in the top right corner of the home screen that opens the other game scene.
// The app holds two complete front ends that share saves and items: Shiba Garden (index.html) and the original
// Lantern Garden (lantern/index.html, the 1.0 build with its own art). This file is loaded by both pages.
"use strict";
(function(){
  const NAMES={shiba:{en:"Shiba Garden","zh-Hant":"柴柴花園",ja:"しばガーデン",ko:"시바 가든",de:"Shiba-Garten",fr:"Jardin Shiba",es:"Jardín Shiba",ar:"حديقة شيبا"},
    lantern:{en:"Lantern Garden","zh-Hant":"燈籠花園",ja:"ランタンガーデン",ko:"랜턴 가든",de:"Laternengarten",fr:"Jardin des lanternes",es:"Jardín de faroles",ar:"حديقة الفوانيس"}};
  const here=/\/lantern\/[^/]*$/.test(location.pathname)?"lantern":"shiba",other=here==="shiba"?"lantern":"shiba",home=document.getElementById("home");if(!home)return;
  const css=document.createElement("style");css.textContent="#sceneBtn{position:absolute;top:calc(env(safe-area-inset-top,0px) + 10px);inset-inline-end:12px;z-index:5;display:flex;align-items:center;gap:6px;height:40px;padding:0 12px 0 6px;border:0;border-radius:20px;background:rgba(255,255,255,.94);color:#24365E;font:700 13px/1 ui-rounded,'SF Pro Rounded',system-ui,sans-serif;box-shadow:0 3px 0 rgba(0,0,0,.18);cursor:pointer}#sceneBtn img{width:30px;height:30px;display:block}#sceneBtn:active{transform:translateY(2px);box-shadow:0 1px 0 rgba(0,0,0,.18)}";
  if(here==="lantern")css.textContent+="#home>h1{margin-top:calc(env(safe-area-inset-top,0px) + 46px)}"; // keep the title clear of the button
  document.head.appendChild(css);
  const b=document.createElement("button"),im=document.createElement("img"),sp=document.createElement("span");b.id="sceneBtn";im.alt="";
  im.src=here==="shiba"?"assets/art/L1_lantern.png":"../assets/art/C1_token.png";b.append(im,sp);home.appendChild(b);
  let shown="";const draw=()=>{const l=document.documentElement.lang||"en",t=(NAMES[other][l]||NAMES[other].en);if(t!==shown){shown=t;sp.textContent=t;b.setAttribute("aria-label",t)}};
  draw();setInterval(draw,400); // both pages set <html lang> when the language changes
  // The app always opens on Shiba Garden; the choice is not remembered between launches.
  b.addEventListener("click",()=>{location.href=here==="shiba"?"lantern/index.html":"../index.html"});
})();
