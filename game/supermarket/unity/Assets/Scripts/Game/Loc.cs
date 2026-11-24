// Text: English and Arabic. Unity's built-in text does not join Arabic letters or run right-to-left,
// so Shape() swaps each letter for its joined form and flips the line.
using System;
using System.Collections.Generic;
using System.Text;

namespace Souq
{
    public static class Loc
    {
        /// 0 English, 1 Arabic, 2 Japanese, 3 Korean, 4 German, 5 French, 6 Spanish, 7 Traditional Chinese
        public static int Lang;
        public static bool Ar => Lang == 1;
        public static bool Cjk => Lang == 2 || Lang == 3 || Lang == 7;
        public static readonly string[] Codes = { "en", "ar", "ja", "ko", "de", "fr", "es", "zh" };
        public static readonly string[] Names = { "English", "العربية", "日本語", "한국어", "Deutsch", "Français", "Español", "繁體中文" };
        public static void Set(string code) { Lang = Math.Max(0, Array.IndexOf(Codes, code)); }
        static readonly Dictionary<string, string[]> S = new Dictionary<string, string[]>
        {
            {"produce", new[]{"Fresh Produce","الخضار والفواكه"}}, {"bakery", new[]{"Bakery","المخبز"}}, {"butcher", new[]{"Deli & Meat","اللحوم والأجبان"}},
            {"seafood", new[]{"Seafood","المأكولات البحرية"}}, {"spices", new[]{"Dairy","الألبان"}}, {"fashion", new[]{"Frozen Foods","المجمدات"}},
            {"fragrance", new[]{"Beverages","المشروبات"}}, {"electronics", new[]{"Snacks","الوجبات الخفيفة"}}, {"phones", new[]{"Pantry","البقالة"}},
            {"jewellery", new[]{"Household","المنزل والتنظيف"}}, {"cars", new[]{"Health & Beauty","الصحة والجمال"}},
            {"build", new[]{"BUILD","بناء"}}, {"upgrade", new[]{"UPGRADE","ترقية"}}, {"level", new[]{"Level","المستوى"}}, {"max", new[]{"MAX","الأقصى"}},
            {"price", new[]{"Sale price","سعر البيع"}}, {"staff", new[]{"Staff","الموظفون"}}, {"hire", new[]{"HIRE","توظيف"}},
            {"speed", new[]{"Service speed","سرعة الخدمة"}}, {"train", new[]{"TRAIN","تدريب"}}, {"permin", new[]{"/min","/دقيقة"}},
            {"next", new[]{"Next bonus at level","المكافأة التالية عند المستوى"}}, {"x1", new[]{"x1","×1"}}, {"x10", new[]{"x10","×10"}}, {"xmax", new[]{"MAX","أقصى"}},
            {"checkouts", new[]{"Checkouts","الكاشير"}}, {"checkout", new[]{"Checkout","كاشير"}}, {"open", new[]{"OPEN","فتح"}},
            {"parking", new[]{"Parking","المواقف"}}, {"spaces", new[]{"Spaces","الأماكن"}}, {"marketing", new[]{"Marketing","التسويق"}},
            {"carsmin", new[]{"Cars per minute","سيارات في الدقيقة"}}, {"expand", new[]{"EXPAND","توسيع"}}, {"promote", new[]{"PROMOTE","ترويج"}},
            {"boosts", new[]{"Managers & Research","المدراء والأبحاث"}}, {"boostsNav", new[]{"Boosts","التطوير"}}, {"gradeNav", new[]{"Grade","الدرجة"}}, {"tasks", new[]{"Tasks","المهام"}}, {"claim", new[]{"CLAIM","استلام"}},
            {"shop", new[]{"Shop","المتجر"}}, {"store", new[]{"Store","المتجر"}}, {"stats", new[]{"Stats","الإحصاءات"}}, {"settings", new[]{"Settings","الإعدادات"}},
            {"grade", new[]{"Store grade","درجة المتجر"}}, {"newstore", new[]{"Move to a bigger store","انتقل إلى متجر أكبر"}}, {"profit", new[]{"Profit","الربح"}},
            {"move", new[]{"MOVE","انتقال"}}, {"income", new[]{"Income","الدخل"}}, {"welcome", new[]{"Welcome back!","أهلاً بعودتك!"}},
            {"away", new[]{"Your store earned while you were away","متجرك ربح أثناء غيابك"}}, {"collect", new[]{"COLLECT","استلام"}},
            {"collect3", new[]{"WATCH AD  x3","شاهد إعلاناً ×3"}}, {"free3", new[]{"COLLECT  x3","استلام ×3"}}, {"capped", new[]{"Earnings stopped after","توقفت الأرباح بعد"}},
            {"hours", new[]{"h","س"}}, {"mins", new[]{"m","د"}}, {"secs", new[]{"s","ث"}},
            {"truck", new[]{"Delivery!","توصيل!"}}, {"vip", new[]{"VIP shopper","عميل مميز"}}, {"vipd", new[]{"A big spender is at the door","عميل كبير عند الباب"}},
            {"bus", new[]{"Tour bus","حافلة سياح"}}, {"busd", new[]{"Bring a bus full of shoppers","أحضر حافلة مليئة بالمتسوقين"}},
            {"qbuy", new[]{"Rush service","خدمة سريعة"}}, {"qbuyd", new[]{"Staff work twice as fast for 2 min","الموظفون أسرع مرتين لدقيقتين"}},
            {"qcheck", new[]{"Express checkout","دفع سريع"}}, {"qcheckd", new[]{"Checkouts twice as fast for 30 s","الكاشير أسرع مرتين لـ 30 ثانية"}},
            {"adboost", new[]{"Ad campaign","حملة إعلانية"}}, {"adboostd", new[]{"Double profit for 30 min","ربح مضاعف لمدة 30 دقيقة"}},
            {"watch", new[]{"WATCH AD","شاهد إعلاناً"}}, {"go", new[]{"GO","ابدأ"}}, {"nothanks", new[]{"No thanks","لا شكراً"}}, {"close", new[]{"Close","إغلاق"}},
            {"gems", new[]{"Gems","الجواهر"}}, {"buy", new[]{"BUY","شراء"}}, {"owned", new[]{"OWNED","مملوك"}}, {"best", new[]{"BEST VALUE","أفضل قيمة"}},
            {"popular", new[]{"POPULAR","الأكثر طلباً"}}, {"starter", new[]{"Starter Pack","باقة البداية"}}, {"starterd", new[]{"300 gems + 4 h of income, once only","300 جوهرة + دخل 4 ساعات، مرة واحدة"}},
            {"noads", new[]{"No Ads","بدون إعلانات"}}, {"noadsd", new[]{"Every ad reward becomes instant","كل مكافآت الإعلانات فورية"}},
            {"x2", new[]{"Double Profit","ربح مضاعف"}}, {"x2d", new[]{"All sales x2, forever","كل المبيعات ×2 إلى الأبد"}},
            {"offpro", new[]{"Night Manager","مدير الليل"}}, {"offprod", new[]{"Earn up to 12 h while away","اربح حتى 12 ساعة أثناء غيابك"}},
            {"warp", new[]{"Time Skip","تخطي الوقت"}}, {"warpd", new[]{"Get this much income right now","احصل على هذا الدخل الآن"}},
            {"stuck", new[]{"Don't want to wait?","لا تريد الانتظار؟"}}, {"needgems", new[]{"Not enough gems","الجواهر غير كافية"}},
            {"test", new[]{"TEST BUILD - purchases are free and not charged","نسخة تجريبية - المشتريات مجانية"}},
            {"sound", new[]{"Sound","الصوت"}}, {"music", new[]{"Music","الموسيقى"}}, {"lang", new[]{"Language","اللغة"}}, {"on", new[]{"ON","تشغيل"}}, {"off", new[]{"OFF","إيقاف"}},
            {"served", new[]{"Shoppers served","عملاء تمت خدمتهم"}}, {"total", new[]{"Total earned","إجمالي الأرباح"}}, {"shoppers", new[]{"Shoppers in store","المتسوقون في المتجر"}},
            {"manager", new[]{"Manager","مدير"}}, {"research", new[]{"Research","أبحاث"}},
            {"e_profit", new[]{"Product Guarantee","ضمان المنتج"}}, {"e_profitd", new[]{"All profit +25%","كل الأرباح +25%"}},
            {"e_walk", new[]{"Eager Shoppers","متسوقون متحمسون"}}, {"e_walkd", new[]{"Shoppers walk 5% faster","المتسوقون أسرع 5%"}},
            {"e_mgrd", new[]{"Staff work 50% faster","الموظفون أسرع 50%"}},
            {"e_truck", new[]{"Fast Delivery","توصيل سريع"}}, {"e_truckd", new[]{"Trucks pay 50% more","الشاحنات تدفع 50% أكثر"}},
            {"e_cash", new[]{"Robot Helpers","روبوتات مساعدة"}}, {"e_cashd", new[]{"Checkouts 5% faster","الكاشير أسرع 5%"}},
            {"e_staff", new[]{"Labour Subsidy","دعم العمالة"}}, {"e_staffd", new[]{"Hiring costs 2% less","التوظيف أرخص 2%"}},
            {"e_ccost", new[]{"Supplier Deal","صفقة الموردين"}}, {"e_ccostd", new[]{"Checkouts cost 2% less","الكاشير أرخص 2%"}},
            {"e_ad", new[]{"Prime Time","وقت الذروة"}}, {"e_add", new[]{"Ad campaign can run 30 min longer","الحملة تستمر 30 دقيقة إضافية"}},
            {"e_resd", new[]{"Upgrades cost 1.9% less","الترقيات أرخص 1.9%"}},
            {"t_lvl", new[]{"Raise {0} to level {1}","ارفع {0} إلى المستوى {1}"}}, {"t_srv", new[]{"Serve {1} shoppers at {0}","اخدم {1} عميل في {0}"}},
            {"t_truck", new[]{"Collect {1} delivery trucks","استلم {1} شاحنة توصيل"}}, {"t_park", new[]{"Expand parking to level {1}","وسّع المواقف إلى المستوى {1}"}},
            {"t_build", new[]{"Build {0}","ابنِ {0}"}}, {"t_star", new[]{"Reach store grade {1}","صل إلى درجة المتجر {1}"}}, {"t_assets", new[]{"Earn {1} in total","اربح {1} إجمالاً"}},
            {"full", new[]{"Checkouts are full! Open or upgrade one.","الكاشير ممتلئ! افتح أو طوّر واحداً."}},
            {"tut1", new[]{"Tap the Fresh Produce section","اضغط على قسم الخضار والفواكه"}}, {"tut2", new[]{"Tap UPGRADE. Hold it to go faster!","اضغط ترقية. اضغط مطولاً للإسراع!"}},
            {"tut3", new[]{"A delivery is here! Tap the truck","وصلت شحنة! اضغط على الشاحنة"}}, {"tut4", new[]{"Open Parking and expand it for more shoppers","افتح المواقف ووسّعها لجذب متسوقين أكثر"}},
            {"tut5", new[]{"Save up and build the Bakery","اجمع المال وابنِ المخبز"}}, {"tutdone", new[]{"Great start! Here is a gift","بداية رائعة! هذه هدية لك"}},
            {"opening", new[]{"GRAND OPENING","الافتتاح الكبير"}}, {"newstoret", new[]{"NEW STORE","متجر جديد"}}, {"title", new[]{"Souq Tycoon","سوق تايكون"}}, {"bonus", new[]{"BONUS","مكافأة"}},
            {"gift", new[]{"Gift!","هدية!"}}, {"daily", new[]{"Daily gift","هدية يومية"}}, {"tap", new[]{"Tap a department to upgrade it","اضغط على قسم لترقيته"}},
        };

        public static string Raw(string key) { string[] v; if (!S.TryGetValue(key, out v)) return key;
            if (Lang >= 2) { string[] x; if (LocMore.X.TryGetValue(key, out x) && Lang - 2 < x.Length && !string.IsNullOrEmpty(x[Lang - 2])) return x[Lang - 2]; return v[0]; }
            return v[Lang];
        }
        public static string G(string key) => Fix(Raw(key));
        public static string F(string key, params object[] a) => Fix(string.Format(Raw(key), a));
        /// Call on any finished line of text before it goes on screen.
        public static string Fix(string s) => Ar ? Shape(s) : s;

        static readonly string[] Unit = { "", "K", "M", "B", "T" };
        public static string Num(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return "-";
            if (v < 0) return "-" + Num(-v);
            if (v < 1000) return v >= 100 ? v.ToString("0") : v.ToString("0.#");
            int e = (int)Math.Floor(Math.Log10(v) / 3);
            double m = v / Math.Pow(1000, e);
            if (m >= 999.5) { m /= 1000; e++; }
            string suffix;
            if (e < Unit.Length) suffix = Unit[e];
            else { int k = e - Unit.Length; suffix = "" + (char)('a' + (k / 26) % 26) + (char)('a' + k % 26); }
            return (m >= 100 ? m.ToString("0") : m >= 10 ? m.ToString("0.#") : m.ToString("0.##")) + suffix;
        }
        public static string Time(double secs)
        {
            if (secs < 0) secs = 0; int t = (int)secs;
            if (t >= 3600) return (t / 3600) + Raw("hours") + " " + ((t % 3600) / 60) + Raw("mins");
            if (t >= 60) return (t / 60) + Raw("mins") + " " + (t % 60) + Raw("secs");
            return t + Raw("secs");
        }

        // ---------- Arabic shaping ----------
        static readonly Dictionary<char, int> Iso = new Dictionary<char, int>(); static readonly HashSet<char> Dual = new HashSet<char>();
        static Loc()
        {
            string dual = "ئبتثجحخسشصضطظعغفقكلمنهي";
            foreach (char c in dual) Dual.Add(c);
            int cp = 0xFE80;
            for (int c = 0x0621; c <= 0x064A; c++)
            {
                if (c >= 0x063B && c <= 0x0640) continue;
                Iso[(char)c] = cp; cp += c == 0x0621 ? 1 : (Dual.Contains((char)c) ? 4 : 2);
            }
        }
        static bool IsLetter(char c) => Iso.ContainsKey(c);
        static bool IsMark(char c) => c >= 0x064B && c <= 0x0652;
        static bool IsLtr(char c) => (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == ',' || c == '%' || c == '+' || c == '$' || c == '/' || c == ':' || c == '-';

        public static string Shape(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            bool any = false; foreach (char c in s) if (IsLetter(c)) { any = true; break; }
            if (!any) return s;
            var o = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (!IsLetter(c)) { o.Append(c); continue; }
                int p = i - 1; while (p >= 0 && IsMark(s[p])) p--;
                int n = i + 1; while (n < s.Length && IsMark(s[n])) n++;
                bool prev = p >= 0 && Dual.Contains(s[p]);
                // lam + alef joins into one glyph
                if (c == 'ل' && n < s.Length && (s[n] == 'ا' || s[n] == 'أ' || s[n] == 'إ' || s[n] == 'آ'))
                {
                    int lig = s[n] == 'ا' ? 0xFEFB : s[n] == 'أ' ? 0xFEF7 : s[n] == 'إ' ? 0xFEF9 : 0xFEF5;
                    o.Append((char)(lig + (prev ? 1 : 0))); i = n; continue;
                }
                bool next = n < s.Length && IsLetter(s[n]) && s[n] != 'ء';
                bool dual = Dual.Contains(c); int iso = Iso[c];
                if (prev && next && dual) o.Append((char)(iso + 3));
                else if (prev && c != 'ء') o.Append((char)(iso + 1));
                else if (next && dual) o.Append((char)(iso + 2));
                else o.Append(c);                                   // stand-alone form: the plain letter
            }
            // flip the line for a left-to-right renderer, keeping numbers and Latin words readable
            var a = o.ToString().ToCharArray(); Array.Reverse(a);
            for (int i = 0; i < a.Length;)
            {
                if (!IsLtr(a[i])) { i++; continue; }
                int j = i; while (j < a.Length && (IsLtr(a[j]) || (a[j] == ' ' && j + 1 < a.Length && IsLtr(a[j + 1])))) j++;
                Array.Reverse(a, i, j - i); i = j;
            }
            for (int i = 0; i < a.Length; i++) { if (a[i] == '(') a[i] = ')'; else if (a[i] == ')') a[i] = '('; }
            return new string(a);
        }
    }
}
