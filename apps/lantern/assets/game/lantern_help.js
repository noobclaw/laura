// Lantern Garden home screen, 1.1.0: the Auto-mark switch is hidden (auto-marking itself stays as the player left it,
// on by default) and a "How to play" chip opens a short rules sheet. Loaded only by the lantern page, after game3d.js.
// The sheet reuses that page's own texts for the rule line and the controls; the extra lines below are new.
"use strict";
(function(){
  const X={en:{t:"How to play",a:"One per colour",b:"One per row and column",c:"Lanterns never touch",d:"A lantern blocks its row, its column, its colour and the tiles around it. Cross those out to find the next one."},
    "zh-Hant":{t:"玩法",a:"一種顏色一盞",b:"同行同列各一盞",c:"燈籠不能相鄰",d:"燈籠會擋住它的行、列、顏色，還有周圍一圈的格子。把這些格子打叉，就能找到下一盞的位置。"},
    ja:{t:"あそびかた",a:"1色に1つ",b:"行と列に1つずつ",c:"灯籠はとなり合わない",d:"灯籠は自分の行・列・色と、まわりのマスをふさぎます。そこに×をつけると次の場所が見つかります。"},
    ko:{t:"게임 방법",a:"색마다 하나",b:"행과 열에 하나씩",c:"등불은 서로 붙지 않아요",d:"등불은 자기 행, 열, 색과 주변 칸을 막아요. 그 칸에 ×를 표시하면 다음 자리를 찾을 수 있어요."},
    de:{t:"So wird gespielt",a:"Eine pro Farbe",b:"Eine pro Reihe und Spalte",c:"Laternen berühren sich nie",d:"Eine Laterne sperrt ihre Reihe, ihre Spalte, ihre Farbe und die Felder um sie herum. Kreuze sie an, um den nächsten Platz zu finden."},
    fr:{t:"Comment jouer",a:"Une par couleur",b:"Une par ligne et colonne",c:"Les lanternes ne se touchent pas",d:"Une lanterne bloque sa ligne, sa colonne, sa couleur et les cases autour d'elle. Barrez-les pour trouver la suivante."},
    es:{t:"Cómo jugar",a:"Uno por color",b:"Uno por fila y columna",c:"Los faroles no se tocan",d:"Un farol bloquea su fila, su columna, su color y las casillas que lo rodean. Táchalas para encontrar el siguiente."},
    ar:{t:"طريقة اللعب",a:"فانوس لكل لون",b:"فانوس لكل صف وعمود",c:"الفوانيس لا تتلامس",d:"الفانوس يحجب صفه وعموده ولونه والخانات المحيطة به. ضع عليها × لتجد المكان التالي."}};
  const auto=document.getElementById("auto"),chips=document.querySelector("#home .chips");if(!chips)return;if(auto)auto.style.display="none";
  const css=document.createElement("style");css.textContent="#helpSheet{position:fixed;inset:0;z-index:40;display:none;align-items:center;justify-content:center;background:rgba(8,6,30,.6)}#helpSheet.on{display:flex}#helpSheet .card{width:min(88vw,340px);max-height:88vh;overflow:auto;padding:20px;border-radius:26px;background:linear-gradient(#3b379a,#211b5c);box-shadow:0 20px 50px rgba(0,0,0,.6);display:flex;flex-direction:column;gap:12px;text-align:center;color:#fff}#helpSheet b{font-size:22px}#helpSheet p{margin:0;font-size:15px;line-height:1.4;color:#dfe2ff}#helpSheet ul{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:6px}#helpSheet li{background:rgba(255,255,255,.12);border-radius:12px;padding:8px 10px;font-weight:700}";
  document.head.appendChild(css);
  const chip=document.createElement("button");chip.className="chip";chip.id="howChip";chip.innerHTML='<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 17h.01"/></svg><span></span>';chips.appendChild(chip);
  const sheet=document.createElement("div");sheet.id="helpSheet";sheet.setAttribute("role","dialog");sheet.innerHTML='<div class="card"><b></b><p></p><ul><li></li><li></li><li></li></ul><p></p><p></p><button class="btn alt"></button></div>';document.body.appendChild(sheet);
  const fillIn=()=>{const l=X[S.lang]?S.lang:"en",x=X[l],ps=sheet.querySelectorAll("p"),li=sheet.querySelectorAll("li");chip.lastChild.textContent=x.t;sheet.querySelector("b").textContent=x.t;
    ps[0].textContent=tr("rules");li[0].textContent=x.a;li[1].textContent=x.b;li[2].textContent=x.c;ps[1].textContent=x.d;ps[2].textContent=tr("how");sheet.querySelector("button").textContent=tr("close")};
  let last="";setInterval(()=>{if(S.lang!==last){last=S.lang;fillIn()}},400);fillIn();
  chip.addEventListener("click",()=>{sfx.tap();fillIn();sheet.classList.add("on")});
  sheet.addEventListener("click",e=>{if(e.target===sheet||e.target.tagName==="BUTTON"){sfx.tap();sheet.classList.remove("on")}});
})();
