// Text for the six further languages. One line per key: key|Japanese|Korean|German|French|Spanish|Traditional Chinese.
// A key that is missing here falls back to English.
using System.Collections.Generic;

namespace Souq
{
    public static class LocMore
    {
        public static readonly Dictionary<string, string[]> X = Parse();
        static Dictionary<string, string[]> Parse()
        {
            var d = new Dictionary<string, string[]>();
            foreach (var raw in Data.Split('\n'))
            {
                var line = raw.Trim(); if (line.Length == 0) continue; var p = line.Split('|'); if (p.Length < 7) continue;
                d[p[0]] = new[] { p[1], p[2], p[3], p[4], p[5], p[6] };
            }
            return d;
        }
        const string Data = @"
produce|青果|청과|Obst & Gemüse|Fruits et légumes|Frutas y verduras|生鮮蔬果
bakery|ベーカリー|베이커리|Bäckerei|Boulangerie|Panadería|麵包坊
butcher|精肉・デリ|정육·델리|Fleisch & Feinkost|Boucherie & traiteur|Carnes y charcutería|肉品熟食
seafood|鮮魚|수산|Fisch & Meeresfrüchte|Poissonnerie|Pescadería|海鮮
spices|乳製品|유제품|Molkerei|Crèmerie|Lácteos|乳製品
fashion|冷凍食品|냉동식품|Tiefkühlkost|Surgelés|Congelados|冷凍食品
fragrance|飲料|음료|Getränke|Boissons|Bebidas|飲料
electronics|お菓子|스낵|Snacks|Snacks|Snacks|零食
phones|食料品|식료품|Vorräte|Épicerie|Despensa|乾貨雜糧
jewellery|日用品|생활용품|Haushalt|Entretien|Hogar|家用清潔
cars|ヘルス＆ビューティー|헬스 & 뷰티|Drogerie|Santé & beauté|Salud y belleza|美妝保健
build|建設|건설|BAUEN|CONSTRUIRE|CONSTRUIR|建造
upgrade|強化|업그레이드|AUSBAUEN|AMÉLIORER|MEJORAR|升級
level|レベル|레벨|Stufe|Niveau|Nivel|等級
max|最大|최대|MAX|MAX|MÁX|已滿
price|販売価格|판매가|Verkaufspreis|Prix de vente|Precio de venta|售價
staff|スタッフ|직원|Personal|Personnel|Personal|店員
hire|雇う|고용|EINSTELLEN|EMBAUCHER|CONTRATAR|僱用
speed|接客スピード|서비스 속도|Servicetempo|Vitesse de service|Velocidad de servicio|服務速度
train|研修|교육|SCHULEN|FORMER|FORMAR|培訓
permin|/分|/분|/Min|/min|/min|/分
next|次のボーナス：レベル|다음 보너스: 레벨|Nächster Bonus bei Stufe|Prochain bonus au niveau|Próximo bono en el nivel|下一個獎勵：等級
xmax|最大|최대|MAX|MAX|MÁX|最大
checkouts|レジ|계산대|Kassen|Caisses|Cajas|收銀台
checkout|レジ|계산대|Kasse|Caisse|Caja|收銀台
open|開く|열기|ÖFFNEN|OUVRIR|ABRIR|開放
parking|駐車場|주차장|Parkplatz|Parking|Aparcamiento|停車場
spaces|台数|주차면|Stellplätze|Places|Plazas|車位
marketing|広告|마케팅|Werbung|Marketing|Marketing|行銷
carsmin|1分あたりの来店車|분당 차량|Autos pro Minute|Voitures par minute|Coches por minuto|每分鐘來車
expand|拡張|확장|ERWEITERN|AGRANDIR|AMPLIAR|擴建
promote|宣伝|홍보|BEWERBEN|PROMOUVOIR|PROMOCIONAR|推廣
boosts|店長と研究|매니저와 연구|Manager & Forschung|Managers & recherche|Gerentes e investigación|店長與研究
boostsNav|強化|부스트|Boosts|Boosts|Mejoras|強化
gradeNav|ランク|등급|Rang|Rang|Rango|店級
tasks|ミッション|미션|Aufgaben|Missions|Misiones|任務
claim|受け取る|받기|ABHOLEN|RÉCUPÉRER|RECOGER|領取
shop|ショップ|상점|Shop|Boutique|Tienda|商店
store|ストア|스토어|Laden|Magasin|Tienda|商店
stats|統計|통계|Statistik|Stats|Estadísticas|統計
settings|設定|설정|Einstellungen|Réglages|Ajustes|設定
grade|店舗ランク|매장 등급|Ladenrang|Rang du magasin|Rango de la tienda|店鋪等級
newstore|もっと大きな店へ移転|더 큰 매장으로 이전|In einen größeren Laden ziehen|Déménager dans un plus grand magasin|Mudarse a una tienda más grande|搬到更大的店面
profit|利益|수익|Gewinn|Profit|Beneficio|利潤
move|移転|이전|UMZIEHEN|DÉMÉNAGER|MUDAR|搬遷
income|収入|수입|Einkommen|Revenu|Ingresos|收入
welcome|おかえりなさい！|다시 오셨군요!|Willkommen zurück!|Bon retour !|¡Bienvenido de nuevo!|歡迎回來！
away|留守の間もお店は稼いでいました|자리를 비운 동안 매장이 벌었어요|Dein Laden hat in deiner Abwesenheit verdient|Votre magasin a gagné en votre absence|Tu tienda ganó mientras no estabas|你不在時店鋪也在賺錢
collect|受け取る|받기|ABHOLEN|RÉCUPÉRER|RECOGER|領取
collect3|広告を見て x3|광고 보고 x3|WERBUNG ANSEHEN  x3|VOIR LA PUB  x3|VER ANUNCIO  x3|看廣告 x3
free3|受け取る x3|받기 x3|ABHOLEN  x3|RÉCUPÉRER  x3|RECOGER  x3|領取 x3
capped|稼ぎが止まった時間：|수익이 멈춘 시간:|Einnahmen gestoppt nach|Gains arrêtés après|Las ganancias pararon tras|收益上限時間：
hours|時間|시간|Std|h|h|時
mins|分|분|Min|min|min|分
secs|秒|초|s|s|s|秒
truck|配達！|배송!|Lieferung!|Livraison !|¡Entrega!|送貨到！
vip|VIPのお客様|VIP 고객|VIP-Kunde|Client VIP|Cliente VIP|VIP 顧客
vipd|大口のお客様が来店中|큰손 고객이 도착했어요|Ein Großkunde steht vor der Tür|Un gros client est à la porte|Un gran comprador está en la puerta|大客戶上門了
bus|観光バス|관광버스|Reisebus|Car de touristes|Autobús turístico|觀光巴士
busd|お客様でいっぱいのバスを呼ぶ|손님 가득한 버스를 부르세요|Hol einen Bus voller Kunden|Faites venir un car plein de clients|Trae un autobús lleno de clientes|叫來一車顧客
qbuy|スピード接客|빠른 서비스|Eilservice|Service express|Servicio rápido|極速服務
qbuyd|2分間スタッフの速さが2倍|2분간 직원 속도 2배|Personal 2 Min doppelt so schnell|Personnel deux fois plus rapide pendant 2 min|El personal va el doble de rápido 2 min|店員速度加倍 2 分鐘
qcheck|スピード会計|빠른 계산|Schnellkasse|Caisse express|Caja rápida|極速結帳
qcheckd|30秒間レジの速さが2倍|30초간 계산대 속도 2배|Kassen 30 s doppelt so schnell|Caisses deux fois plus rapides pendant 30 s|Cajas el doble de rápido 30 s|收銀速度加倍 30 秒
adboost|広告キャンペーン|광고 캠페인|Werbekampagne|Campagne de pub|Campaña publicitaria|廣告活動
adboostd|30分間利益2倍|30분간 수익 2배|30 Min doppelter Gewinn|Profit doublé pendant 30 min|Beneficio doble 30 min|30 分鐘雙倍利潤
watch|広告を見る|광고 보기|WERBUNG ANSEHEN|VOIR LA PUB|VER ANUNCIO|看廣告
go|スタート|시작|LOS|GO|YA|開始
nothanks|いいえ|괜찮아요|Nein danke|Non merci|No, gracias|不用了
close|閉じる|닫기|Schließen|Fermer|Cerrar|關閉
gems|ジェム|보석|Juwelen|Gemmes|Gemas|寶石
buy|購入|구매|KAUFEN|ACHETER|COMPRAR|購買
owned|購入済み|보유 중|GEKAUFT|ACQUIS|COMPRADO|已擁有
best|一番お得|최고 가성비|BESTER WERT|MEILLEURE OFFRE|MEJOR OFERTA|最超值
popular|人気|인기|BELIEBT|POPULAIRE|POPULAR|熱門
starter|スターターパック|스타터 팩|Starterpaket|Pack de départ|Pack inicial|新手禮包
starterd|ジェム300個＋4時間分の収入（1回限り）|보석 300개 + 4시간 수입, 1회 한정|300 Juwelen + 4 Std Einkommen, nur einmal|300 gemmes + 4 h de revenu, une seule fois|300 gemas + 4 h de ingresos, solo una vez|300 寶石＋4 小時收入，限購一次
noads|広告なし|광고 제거|Keine Werbung|Sans pub|Sin anuncios|免廣告
noadsd|広告報酬がすぐにもらえる|광고 보상을 즉시 획득|Jede Werbebelohnung sofort|Toutes les récompenses pub sont instantanées|Todas las recompensas de anuncios al instante|所有廣告獎勵立即領取
x2|利益2倍|수익 2배|Doppelter Gewinn|Profit doublé|Beneficio doble|雙倍利潤
x2d|すべての売上がずっと2倍|모든 판매 영구 2배|Alle Verkäufe x2, für immer|Toutes les ventes x2, pour toujours|Todas las ventas x2, para siempre|所有銷售永久 x2
offpro|夜間マネージャー|야간 매니저|Nachtmanager|Gérant de nuit|Gerente nocturno|夜班經理
offprod|留守中も最大12時間稼ぐ|부재 중 최대 12시간 수익|Verdiene bis zu 12 Std in Abwesenheit|Gagnez jusqu'à 12 h en votre absence|Gana hasta 12 h mientras no estás|離線最多賺 12 小時
warp|タイムスキップ|시간 건너뛰기|Zeitsprung|Saut dans le temps|Salto de tiempo|時間跳躍
warpd|この収入を今すぐ受け取る|이만큼의 수입을 지금 받기|Erhalte dieses Einkommen sofort|Recevez ce revenu tout de suite|Recibe estos ingresos ahora mismo|立即獲得這些收入
stuck|待ちたくない？|기다리기 싫으세요?|Keine Lust zu warten?|Pas envie d'attendre ?|¿No quieres esperar?|不想等？
needgems|ジェムが足りません|보석이 부족해요|Nicht genug Juwelen|Pas assez de gemmes|No hay suficientes gemas|寶石不足
test|テスト版 - 購入は無料で課金されません|테스트 빌드 - 구매는 무료이며 청구되지 않습니다|TESTVERSION - Käufe sind gratis und werden nicht berechnet|VERSION TEST - achats gratuits, rien n'est débité|VERSIÓN DE PRUEBA - las compras son gratis y no se cobran|測試版 - 購買免費，不會扣款
sound|効果音|효과음|Ton|Son|Sonido|音效
music|音楽|음악|Musik|Musique|Música|音樂
lang|言語|언어|Sprache|Langue|Idioma|語言
on|オン|켜짐|AN|OUI|SÍ|開
off|オフ|꺼짐|AUS|NON|NO|關
served|接客したお客様|응대한 고객|Bediente Kunden|Clients servis|Clientes atendidos|已服務顧客
total|累計収益|총 수익|Gesamt verdient|Total gagné|Total ganado|累計收益
shoppers|来店中のお客様|매장 내 고객|Kunden im Laden|Clients en magasin|Clientes en la tienda|店內顧客
manager|店長|매니저|Manager|Manager|Gerente|店長
research|研究|연구|Forschung|Recherche|Investigación|研究
e_profit|品質保証|품질 보증|Produktgarantie|Garantie produit|Garantía de producto|品質保證
e_profitd|すべての利益 x2|모든 수익 x2|Gesamter Gewinn x2|Tout le profit x2|Todo el beneficio x2|所有利潤 x2
e_walk|やる気満々のお客様|의욕적인 고객|Eifrige Kunden|Clients pressés|Clientes con ganas|積極的顧客
e_walkd|お客様の歩く速さ +5%|고객 이동 속도 +5%|Kunden gehen 5% schneller|Les clients marchent 5% plus vite|Los clientes caminan un 5% más rápido|顧客步行速度 +5%
e_mgrd|スタッフの速さ +50%|직원 속도 +50%|Personal arbeitet 50% schneller|Personnel 50% plus rapide|El personal trabaja un 50% más rápido|店員速度 +50%
e_truck|スピード配達|빠른 배송|Schnelllieferung|Livraison rapide|Entrega rápida|快速送貨
e_truckd|トラックの報酬 +50%|트럭 보상 +50%|Lieferungen zahlen 50% mehr|Les camions rapportent 50% de plus|Los camiones pagan un 50% más|貨車報酬 +50%
e_cash|ロボットヘルパー|로봇 도우미|Roboterhelfer|Robots assistants|Robots ayudantes|機器人幫手
e_cashd|レジの速さ +5%|계산대 속도 +5%|Kassen 5% schneller|Caisses 5% plus rapides|Cajas un 5% más rápidas|收銀速度 +5%
e_staff|雇用助成|고용 지원금|Lohnzuschuss|Aide à l'embauche|Subsidio laboral|僱用補助
e_staffd|雇用コスト -2%|고용 비용 -2%|Einstellen kostet 2% weniger|Embaucher coûte 2% de moins|Contratar cuesta un 2% menos|僱用成本 -2%
e_ccost|仕入れ契約|공급 계약|Lieferantendeal|Accord fournisseur|Acuerdo con proveedores|供應商合約
e_ccostd|レジのコスト -2%|계산대 비용 -2%|Kassen kosten 2% weniger|Les caisses coûtent 2% de moins|Las cajas cuestan un 2% menos|收銀台成本 -2%
e_ad|ゴールデンタイム|프라임 타임|Beste Sendezeit|Heure de grande écoute|Horario estelar|黃金時段
e_add|広告キャンペーンを30分延長できる|광고 캠페인을 30분 더 진행|Werbekampagne kann 30 Min länger laufen|La campagne peut durer 30 min de plus|La campaña puede durar 30 min más|廣告活動可延長 30 分鐘
e_resd|強化コスト -1.9%|업그레이드 비용 -1.9%|Ausbau kostet 1,9% weniger|Les améliorations coûtent 1,9% de moins|Las mejoras cuestan un 1,9% menos|升級成本 -1.9%
t_lvl|{0}をレベル{1}にする|{0}을(를) 레벨 {1}까지 올리기|{0} auf Stufe {1} bringen|Monter {0} au niveau {1}|Sube {0} al nivel {1}|將{0}升到等級 {1}
t_srv|{0}で{1}人を接客する|{0}에서 고객 {1}명 응대|{1} Kunden bei {0} bedienen|Servir {1} clients au rayon {0}|Atiende a {1} clientes en {0}|在{0}服務 {1} 位顧客
t_truck|配達トラックを{1}台受け取る|배송 트럭 {1}대 받기|{1} Lieferungen annehmen|Récupérer {1} livraisons|Recoge {1} camiones de reparto|領取 {1} 輛送貨車
t_park|駐車場をレベル{1}に拡張|주차장을 레벨 {1}까지 확장|Parkplatz auf Stufe {1} erweitern|Agrandir le parking au niveau {1}|Amplía el aparcamiento al nivel {1}|將停車場擴建到等級 {1}
t_build|{0}を建設する|{0} 건설하기|{0} bauen|Construire {0}|Construye {0}|建造{0}
t_star|店舗ランク{1}に到達|매장 등급 {1} 달성|Ladenrang {1} erreichen|Atteindre le rang {1}|Alcanza el rango de tienda {1}|達到店鋪等級 {1}
t_assets|合計{1}を稼ぐ|총 {1} 벌기|Insgesamt {1} verdienen|Gagner {1} au total|Gana {1} en total|累計賺取 {1}
full|レジが満員です！新しく開くか強化しましょう。|계산대가 꽉 찼어요! 새로 열거나 업그레이드하세요.|Die Kassen sind voll! Öffne oder verbessere eine.|Les caisses sont pleines ! Ouvrez-en ou améliorez-en une.|¡Las cajas están llenas! Abre o mejora una.|收銀台滿了！開新的或升級一台。
tut1|青果コーナーをタップ|청과 코너를 탭하세요|Tippe auf Obst & Gemüse|Touchez le rayon Fruits et légumes|Toca la sección de Frutas y verduras|點一下生鮮蔬果區
tut2|「強化」をタップ。長押しでもっと速く！|업그레이드를 탭! 길게 누르면 더 빨라요!|Tippe auf AUSBAUEN. Halten geht schneller!|Touchez AMÉLIORER. Maintenez pour aller plus vite !|Toca MEJORAR. ¡Mantén pulsado para ir más rápido!|點「升級」，長按可以更快！
tut3|配達が来ました！トラックをタップ|배송이 도착했어요! 트럭을 탭하세요|Eine Lieferung ist da! Tippe auf den Lkw|Une livraison est arrivée ! Touchez le camion|¡Llegó una entrega! Toca el camión|貨到了！點一下貨車
tut4|駐車場を開いて拡張し、お客様を増やそう|주차장을 열고 확장해 고객을 늘리세요|Öffne den Parkplatz und erweitere ihn für mehr Kunden|Ouvrez le parking et agrandissez-le pour plus de clients|Abre el aparcamiento y amplíalo para más clientes|打開停車場並擴建，吸引更多顧客
tut5|お金を貯めてベーカリーを建てよう|돈을 모아 베이커리를 지으세요|Spare und baue die Bäckerei|Économisez et construisez la Boulangerie|Ahorra y construye la Panadería|存錢建造麵包坊
tutdone|いいスタート！プレゼントをどうぞ|좋은 출발! 선물을 받으세요|Toller Start! Hier ist ein Geschenk|Bon début ! Voici un cadeau|¡Gran comienzo! Aquí tienes un regalo|好的開始！送你一份禮物
opening|グランドオープン|그랜드 오픈|GROSSE ERÖFFNUNG|GRANDE OUVERTURE|GRAN INAUGURACIÓN|盛大開幕
newstoret|新店舗|새 매장|NEUER LADEN|NOUVEAU MAGASIN|NUEVA TIENDA|全新店面
title|Souq Tycoon|Souq Tycoon|Souq Tycoon|Souq Tycoon|Souq Tycoon|Souq Tycoon
bonus|ボーナス|보너스|BONUS|BONUS|BONO|獎勵
gift|プレゼント！|선물!|Geschenk!|Cadeau !|¡Regalo!|禮物！
daily|デイリーギフト|일일 선물|Tagesgeschenk|Cadeau du jour|Regalo diario|每日禮物
tap|売り場をタップして強化|코너를 탭해 업그레이드하세요|Tippe auf eine Abteilung, um sie auszubauen|Touchez un rayon pour l'améliorer|Toca una sección para mejorarla|點一下部門即可升級
";
    }
}
