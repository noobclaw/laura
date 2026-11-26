# App Store listing for Accord (used by scripts/asc_release.py; listing.md is generated from this file).
# Limits: name ≤ 30, subtitle ≤ 30, keywords ≤ 100 characters.

EN_DESC = """Your perfume formula book, calculator and lab notebook in one.

Accord is made for people who blend at home: perfumers in training, candle and soap makers, anyone with a scale, a pipette and a shelf of little bottles.

FORMULATE
• Enter each material in grams, drops or percent and switch any line with one tap
• Mark dilutions (10 %, 1 %, your own) and the solvent; analysis counts only the active material
• Use your own accords as bases inside other formulas. Accord unpacks them and guards against loops (Pro)
• Flag lines after a trial: too strong, too weak, just right

SEE THE SCENT
• Evaporation timeline: drag through 24 hours to see which materials you’ll smell after 10 minutes, 2 hours, 8 hours
• Five-tier pyramid and olfactive family ring
• Naturals share, backbone material and estimated longevity

MAKE IT
• Scale to a 50 ml bottle at EdP, EdT, Extrait or your own load, or to a target weight or factor
• Weighing mode: one material at a time in big type, running scale total, off-target warnings, screen stays on
• Save the batch, subtract it from stock and keep a maturation diary with reminders on day 7, 14 and 28 (Pro)

STAY ORGANISED
• Material library with 52 starter materials, families, evaporation tiers and drops per gram
• Your own maximum per material, checked against the finished product, with the highest safe load
• Stock, cost per gram, shelf life and cost per bottle (Pro)
• Compare two versions and see every material that moved (Pro)
• Import your spreadsheet; export CSV, PDF and Markdown; full backup file (Pro)
• App Lock with Face ID (Pro)
• 10 languages, switchable inside the app

Private by design: no account, no server, no tracking. Your formulas stay on your iPhone.

Accord Pro is a one-time purchase, not a subscription. Free: 5 formulas with the full calculator and analysis.

Accord checks against the limits you enter; it is not a regulatory assessment. Always follow your suppliers’ safety documents."""

PRO_LINE = {
    "zh-Hant": "Accord Pro 一次買斷，不是訂閱。免費版可存 5 個配方，計算與分析全部可用。\n\nAccord 只和你輸入的上限比較，不是法規評估；請以供應商的安全文件為準。",
    "zh-Hans": "Accord Pro 一次买断，不是订阅。免费版可存 5 个配方，计算与分析全部可用。\n\nAccord 只和你输入的上限比较，不是法规评估；请以供应商的安全文件为准。",
    "ja": "Accord Pro は買い切りでサブスクではありません。無料版でも処方 5 件まで、計算と分析はすべて使えます。\n\nAccord はあなたが入力した上限と比べるだけで、法規の評価ではありません。仕入れ先の安全資料に従ってください。",
    "ko": "Accord Pro는 한 번 구매로 끝, 구독이 아닙니다. 무료로도 처방 5개와 모든 계산·분석을 쓸 수 있습니다.\n\nAccord는 입력한 한도와 비교할 뿐 규제 평가가 아닙니다. 공급업체의 안전 문서를 따르세요.",
    "de-DE": "Accord Pro ist ein Einmalkauf, kein Abo. Gratis: 5 Rezepte mit vollem Rechner und Analyse.\n\nAccord vergleicht mit deinen eigenen Grenzwerten; das ist keine regulatorische Bewertung. Halte dich an die Sicherheitsunterlagen deiner Lieferanten.",
    "fr-FR": "Accord Pro s’achète une fois, sans abonnement. Gratuit : 5 formules avec calculs et analyse complets.\n\nAccord compare avec vos propres limites ; ce n’est pas une évaluation réglementaire. Suivez toujours les documents de sécurité de vos fournisseurs.",
    "es-ES": "Accord Pro es un pago único, sin suscripción. Gratis: 5 fórmulas con cálculo y análisis completos.\n\nAccord compara con tus propios límites; no es una evaluación regulatoria. Sigue siempre los documentos de seguridad de tus proveedores.",
    "pt-BR": "O Accord Pro é compra única, sem assinatura. Grátis: 5 fórmulas com cálculo e análise completos.\n\nO Accord compara com seus próprios limites; não é uma avaliação regulatória. Siga sempre os documentos de segurança dos seus fornecedores.",
    "it": "Accord Pro è un acquisto unico, senza abbonamento. Gratis: 5 formule con calcolo e analisi completi.\n\nAccord confronta con i tuoi limiti; non è una valutazione normativa. Segui sempre i documenti di sicurezza dei fornitori.",
}

# locale: (name, subtitle, keywords, description intro or None for English)
LOCALES = {
    "en-US": ("Accord: Perfume Formula Lab", "Blend, weigh and age fragrance",
              "perfume,fragrance,formula,perfumery,diy,candle,soap,essential oil,dilution,ifra,blend,scent,diffuser", None),
    "zh-Hant": ("Accord：香水配方調香台", "調配、秤量、熟成你的香水", "香水,調香,配方,精油,香氛,蠟燭,手工皂,稀釋,擴香,香精,DIY,香調",
                "你的香水配方本、計算機和實驗筆記，全在一個 App。給在家調香的人：調香學徒、香氛蠟燭和手工皂作者，所有拿著秤、滴管和一排小瓶子的人。\n\n• 每種原料用克、滴或百分比輸入，點一下就切換單位\n• 標註稀釋濃度與溶劑，分析只計算有效成分\n• 把自己的和弦當基底放進其他配方，自動展開（Pro）\n• 揮發時間軸：拖動看 10 分鐘、2 小時、8 小時後聞到什麼\n• 五層金字塔與香調家族環圖、天然比例、估計持久度\n• 依 50 ml 淡香精等濃度放大，大字秤量模式一次一種原料\n• 儲存批次、扣庫存，第 7、14、28 天提醒你寫熟成日記（Pro）\n• 52 種起步原料、你自己的最高用量檢查、庫存與成本（Pro）\n• 版本比較、試算表匯入、CSV／PDF／Markdown 匯出與備份（Pro）\n• Face ID 鎖定（Pro）、10 種語言 App 內切換\n\n沒有帳號、沒有伺服器、不追蹤，配方只留在你的 iPhone。"),
    "zh-Hans": ("Accord：香水配方调香台", "调配、称量、熟成你的香水", "香水,调香,配方,精油,香氛,蜡烛,手工皂,稀释,扩香,香精,DIY,香调",
                "你的香水配方本、计算器和实验笔记，全在一个 App。给在家调香的人：调香学徒、香氛蜡烛和手工皂作者，所有拿着秤、滴管和一排小瓶子的人。\n\n• 每种原料用克、滴或百分比输入，点一下就切换单位\n• 标注稀释浓度与溶剂，分析只计算有效成分\n• 把自己的和弦当基底放进其他配方，自动展开（Pro）\n• 挥发时间轴：拖动看 10 分钟、2 小时、8 小时后闻到什么\n• 五层金字塔与香调家族环图、天然比例、估计持久度\n• 按 50 ml 淡香精等浓度放大，大字称量模式一次一种原料\n• 保存批次、扣库存，第 7、14、28 天提醒你写熟成日记（Pro）\n• 52 种起步原料、你自己的最高用量检查、库存与成本（Pro）\n• 版本比较、电子表格导入、CSV／PDF／Markdown 导出与备份（Pro）\n• Face ID 锁定（Pro）、10 种语言 App 内切换\n\n没有账号、没有服务器、不追踪，配方只留在你的 iPhone。"),
    "ja": ("Accord：香水の処方と調香ノート", "調合・計量・熟成をひとつに", "香水,調香,処方,アロマ,精油,キャンドル,石けん,希釈,ディフューザー,フレグランス,DIY",
           "香水の処方ノート、計算機、実験ノートがひとつに。家で調香する人のためのアプリです：調香の学び手、キャンドルや石けんの作り手、はかりとピペットと小瓶を並べるすべての人へ。\n\n• 原料をグラム・滴・% で入力、ワンタップで単位を切り替え\n• 希釈と溶剤を記録、分析は有効成分だけで計算\n• 自作アコードを別の処方のベースとして使用、自動で展開（Pro）\n• 揮発タイムライン：10 分後・2 時間後・8 時間後の香りをドラッグで確認\n• 5 段のピラミッドと香りの系統、天然比率、持続時間の目安\n• 50 ml のオードパルファムなどに換算、大きな文字の計量モード\n• バッチを保存して在庫から差し引き、7・14・28 日目に熟成日記の通知（Pro）\n• 52 種の原料つき、自分の上限チェック、在庫とコスト（Pro）\n• バージョン比較、表計算の読み込み、CSV／PDF／Markdown 書き出しとバックアップ（Pro）\n• Face ID ロック（Pro）、アプリ内で 10 言語を切り替え\n\nアカウントもサーバーもトラッキングもなし。処方は iPhone の中だけに。"),
    "ko": ("Accord: 향수 조향 노트", "조향, 계량, 숙성을 한곳에서", "향수,조향,처방,에센셜오일,캔들,비누,희석,디퓨저,향료,DIY,블렌딩,향",
           "향수 처방 노트, 계산기, 실험 일지를 하나로. 집에서 조향하는 사람을 위한 앱입니다: 조향을 배우는 분, 캔들·비누 제작자, 저울과 피펫과 작은 병들을 가진 모든 분.\n\n• 원료를 그램, 방울, 퍼센트로 입력하고 한 번 탭해 단위 전환\n• 희석 농도와 용매를 기록, 분석은 유효 성분만 계산\n• 내 어코드를 다른 처방의 베이스로 사용, 자동으로 풀어 계산 (Pro)\n• 휘발 타임라인: 10분, 2시간, 8시간 뒤의 향을 드래그로 확인\n• 5단 피라미드와 향 계열 차트, 천연 비율, 예상 지속 시간\n• 50 ml 오 드 퍼퓸 등으로 환산, 큰 글씨 계량 모드\n• 배치 저장과 재고 차감, 7·14·28일째 숙성 일지 알림 (Pro)\n• 기본 원료 52종, 나만의 최대치 확인, 재고와 원가 (Pro)\n• 버전 비교, 스프레드시트 가져오기, CSV/PDF/Markdown 내보내기와 백업 (Pro)\n• Face ID 잠금 (Pro), 앱 안에서 10개 언어 전환\n\n계정도 서버도 추적도 없습니다. 처방은 iPhone에만 남습니다."),
    "de-DE": ("Accord: Parfüm-Rezepte", "Mischen, wiegen, reifen lassen", "parfüm,duft,rezept,parfümerie,diy,kerze,seife,ätherisches öl,verdünnung,ifra,duftöl",
              "Dein Parfüm-Rezeptbuch, Rechner und Laborheft in einem. Für alle, die zu Hause mischen: Parfümeure in Ausbildung, Kerzen- und Seifenmacher, alle mit Waage, Pipette und einem Regal voller Fläschchen.\n\n• Rohstoffe in Gramm, Tropfen oder Prozent eingeben, Einheit mit einem Tipp wechseln\n• Verdünnungen und Lösungsmittel vermerken; die Analyse zählt nur den Wirkstoff\n• Eigene Akkorde als Basis in anderen Rezepten, automatisch aufgelöst (Pro)\n• Verdunstungsverlauf: zieh durch 24 Stunden und sieh, was nach 10 Minuten, 2 oder 8 Stunden riecht\n• Fünfstufige Duftpyramide, Duftfamilien, Naturstoffanteil, geschätzte Haltbarkeit\n• Auf 50 ml Eau de Parfum hochrechnen, Wiegemodus in großer Schrift\n• Charge speichern, vom Bestand abziehen, Reifetagebuch mit Erinnerung an Tag 7, 14 und 28 (Pro)\n• 52 Startrohstoffe, eigene Höchstwerte, Bestand und Kosten (Pro)\n• Versionen vergleichen, Tabellen importieren, CSV/PDF/Markdown exportieren, Backup (Pro)\n• App-Sperre mit Face ID (Pro), 10 Sprachen direkt in der App\n\nKein Konto, kein Server, kein Tracking. Deine Rezepte bleiben auf deinem iPhone."),
    "fr-FR": ("Accord: formules de parfum", "Composer, peser, faire mûrir", "parfum,parfumerie,formule,diy,bougie,savon,huile essentielle,dilution,ifra,senteur,orgue",
              "Votre carnet de formules, calculatrice et cahier de labo réunis. Pour celles et ceux qui composent chez eux : apprentis parfumeurs, créateurs de bougies et de savons, tous ceux qui ont une balance, une pipette et une étagère de flacons.\n\n• Saisissez chaque matière en grammes, gouttes ou pourcentage et changez d’unité d’un geste\n• Notez dilutions et solvants ; l’analyse ne compte que la matière active\n• Utilisez vos accords comme bases dans d’autres formules, dépliés automatiquement (Pro)\n• Évolution de l’évaporation : faites glisser sur 24 h pour voir ce qu’on sent après 10 min, 2 h, 8 h\n• Pyramide à cinq niveaux, familles olfactives, part de naturels, tenue estimée\n• Mise à l’échelle pour un flacon de 50 ml, mode pesée en grands caractères\n• Enregistrez le lot, déduisez le stock, journal de maturation avec rappels aux jours 7, 14 et 28 (Pro)\n• 52 matières de départ, vos propres limites, stock et coût (Pro)\n• Comparaison de versions, import de tableur, export CSV/PDF/Markdown et sauvegarde (Pro)\n• Verrouillage Face ID (Pro), 10 langues dans l’app\n\nNi compte, ni serveur, ni pistage. Vos formules restent sur votre iPhone."),
    "es-ES": ("Accord: fórmulas de perfume", "Mezcla, pesa y deja madurar", "perfume,perfumería,fórmula,diy,vela,jabón,aceite esencial,dilución,ifra,fragancia,aroma",
              "Tu libro de fórmulas, calculadora y cuaderno de laboratorio en uno. Para quien mezcla en casa: aprendices de perfumista, creadores de velas y jabones, cualquiera con una báscula, una pipeta y un estante de frasquitos.\n\n• Introduce cada material en gramos, gotas o porcentaje y cambia de unidad con un toque\n• Anota diluciones y disolventes; el análisis solo cuenta el material activo\n• Usa tus acordes como bases dentro de otras fórmulas, desglosados automáticamente (Pro)\n• Línea de evaporación: desliza por 24 horas y mira qué huele a los 10 min, 2 h, 8 h\n• Pirámide de cinco niveles, familias olfativas, porcentaje natural, duración estimada\n• Escala a un frasco de 50 ml, modo de pesado con letra grande\n• Guarda el lote, réstalo del stock y lleva un diario de maduración con avisos los días 7, 14 y 28 (Pro)\n• 52 materiales iniciales, tus propios límites, stock y coste (Pro)\n• Comparar versiones, importar hojas de cálculo, exportar CSV/PDF/Markdown y copia de seguridad (Pro)\n• Bloqueo con Face ID (Pro), 10 idiomas dentro de la app\n\nSin cuenta, sin servidor, sin rastreo. Tus fórmulas se quedan en tu iPhone."),
    "pt-BR": ("Accord: fórmulas de perfume", "Misture, pese e deixe maturar", "perfume,perfumaria,fórmula,diy,vela,sabonete,óleo essencial,diluição,ifra,fragrância,aroma",
              "Seu caderno de fórmulas, calculadora e diário de laboratório em um só app. Para quem mistura em casa: aprendizes de perfumista, quem faz velas e sabonetes, qualquer pessoa com balança, pipeta e uma prateleira de frasquinhos.\n\n• Informe cada material em gramas, gotas ou porcentagem e troque a unidade com um toque\n• Anote diluições e solventes; a análise conta só o material ativo\n• Use seus acordes como bases em outras fórmulas, desdobrados automaticamente (Pro)\n• Linha de evaporação: arraste por 24 horas e veja o que se sente após 10 min, 2 h, 8 h\n• Pirâmide de cinco níveis, famílias olfativas, porcentagem natural, fixação estimada\n• Escale para um frasco de 50 ml, modo de pesagem com letras grandes\n• Salve o lote, desconte do estoque e mantenha um diário de maturação com lembretes nos dias 7, 14 e 28 (Pro)\n• 52 materiais iniciais, seus próprios limites, estoque e custo (Pro)\n• Comparar versões, importar planilhas, exportar CSV/PDF/Markdown e backup (Pro)\n• Bloqueio com Face ID (Pro), 10 idiomas dentro do app\n\nSem conta, sem servidor, sem rastreamento. Suas fórmulas ficam no seu iPhone."),
    "it": ("Accord: formule di profumo", "Componi, pesa, fai maturare", "profumo,profumeria,formula,diy,candela,sapone,olio essenziale,diluizione,ifra,fragranza",
           "Il tuo quaderno di formule, calcolatrice e diario di laboratorio in uno. Per chi crea in casa: aspiranti profumieri, chi fa candele e saponi, chiunque abbia una bilancia, una pipetta e uno scaffale di boccette.\n\n• Inserisci ogni materiale in grammi, gocce o percentuale e cambia unità con un tocco\n• Annota diluizioni e solventi; l’analisi conta solo il materiale attivo\n• Usa i tuoi accordi come basi in altre formule, scomposti in automatico (Pro)\n• Andamento dell’evaporazione: scorri 24 ore e vedi cosa si sente dopo 10 min, 2 h, 8 h\n• Piramide a cinque livelli, famiglie olfattive, quota di naturali, durata stimata\n• Scala per un flacone da 50 ml, modalità pesata a caratteri grandi\n• Salva il lotto, scala le scorte e tieni un diario di maturazione con promemoria ai giorni 7, 14 e 28 (Pro)\n• 52 materiali iniziali, i tuoi limiti, scorte e costi (Pro)\n• Confronto versioni, importazione da fogli di calcolo, esportazione CSV/PDF/Markdown e backup (Pro)\n• Blocco con Face ID (Pro), 10 lingue nell’app\n\nNessun account, nessun server, nessun tracciamento. Le tue formule restano sul tuo iPhone."),
}

SHOT_DIRS = {"en-US": "en-US", "zh-Hant": "zh-Hant", "de-DE": "de-DE", "ja": "ja"}

REVIEW_NOTES = ("No account or login is needed. The app opens on a sample formula (Evening Amber) so every feature can be tried "
                "immediately: tap Weigh to plan a 50 ml bottle and step through weighing mode; Analysis shows the pyramid and "
                "families; Product shows the limit check. Pro is a one-time non-consumable purchase: creating a sixth formula, "
                "comparing versions, exporting, or saving a batch opens the paywall with Restore Purchase. Notifications are "
                "requested only when a batch is saved (maturation reminders). Face ID is used only if the user turns on App Lock. "
                "No data leaves the device.")

if __name__ == "__main__":
    # Length check and listing.md
    out = ["# Accord — App Store listing (generated from listing.py)\n"]
    for loc, (name, sub, kw, intro) in LOCALES.items():
        assert len(name) <= 30, (loc, "name", len(name))
        assert len(sub) <= 30, (loc, "subtitle", len(sub))
        assert len(kw) <= 100, (loc, "keywords", len(kw))
        desc = EN_DESC if intro is None else intro + "\n\n" + PRO_LINE[loc]
        assert len(desc) <= 4000, (loc, "description", len(desc))
        out.append(f"## {loc}\n\n- **Name** ({len(name)}): {name}\n- **Subtitle** ({len(sub)}): {sub}\n- **Keywords** ({len(kw)}): {kw}\n\n{desc}\n")
    out.append("## Review notes\n\n" + REVIEW_NOTES + "\n")
    import os
    open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "listing.md"), "w").write("\n".join(out))
    print("ok", len(LOCALES), "locales")
