# سناریوی اجرایی Softphone سازمانی حسابیکس — رله رسانه از طریق Connector

**کد افزونه:** `asterisk_issabel_connector`  
**نام قابلیت:** Softphone داخل‌برنامه‌ای (حالت رله + حالت مستقیم اختیاری)  
**نسخه سند:** `1.2.0`  
**تاریخ:** ۱۴۰۵/۰۵/۱۵ (2026-08-06)  
**وضعیت:** پیاده‌سازی فعال — R1 تقریباً کامل (باقی: UAT Issabel واقعی)  
**وابستگی پایه:** سند `TELEPHONY_ASTERISK_ISSABEL_PLUGIN_EXECUTION_PLAN.md` (فازهای ۰–۴ CTI موجود)

### پیشرفت پیاده‌سازی (به‌روز ۱۴۰۵/۰۵/۱۵ — جلسه ۲)

| فاز | وضعیت | توضیح |
|-----|--------|--------|
| R0 | ✅ جزئی / در lab | قرارداد پروتکل، AudioSocket، تونل WSS، پروفایل `pcm_ws_v1` |
| R1 | ✅ کامل‌شده در کد (به‌جز UAT فیزیکی) | میکروفون/پخش واقعی، UI endpoint_mode، Phone Bar، Click-to-Call→Relay |
| R2–R5 | ⏳ نشده | طبق برنامه |

**تصمیم اجرایی R0 (انحراف کنترل‌شده از aiortc روز اول):**  
مسیر رسانه فاز ۱ = **PCM16LE 8kHz روی WSS** (`pcm_ws_v1`) بین کلاینت ↔ Media Hub ↔ Connector ↔ AudioSocket. این بدون لایسنس، بدون expose کردن PJSIP، و سازگار با Asterisk است. ارتقا به WebRTC/aiortc/Opus در R3 به‌عنوان transport جایگزین پشت همان سشن/تونل انجام می‌شود.

---

## ۰. خلاصه اجرایی

امروز افزونهٔ تلفن حسابیکس یک **CTI کامل** است (Screen Pop، Click-to-Call، تاریخچه، ضبط، داشبورد، کنترل تماس) ولی **رسانهٔ صوت داخل اپ وجود ندارد**؛ اپراتور هنوز به Softphone/تلفن SIP خارجی وابسته است.

بسیاری از سازمان‌ها **دسترسی بیرونی به PBX را می‌بندند** (هیچ WSS/SIP/RTP ورودی از اینترنت به Issabel). بنابراین رجیستر مستقیم PJSIP/WebRTC از بیرون برای آن‌ها عملاً غیرممکن یا ناامن است.

**تصمیم قفل‌شده این سند:**

| موضوع | تصمیم |
|--------|--------|
| حالت پیش‌فرض Softphone | **Media Relay** از طریق Connector — بدون باز کردن پورت PBX به اینترنت |
| حالت اختیاری | **Direct WebRTC/PJSIP** برای سازمان‌هایی که VPN/LAN یا WSS عمومی دارند |
| مسیر صدا در Relay | کلاینت ↔ لبه رسانه حسابیکس ↔ تونل خروجی Connector ↔ Asterisk محلی |
| مسیر کنترل/CRM | همان CTI فعلی (AMI + API + WS) |
| ابزارها | **فقط OSS بدون لایسنس تجاری** |
| Desk Phone / Click-to-Call | حفظ می‌شود (حالت سوم) |

هدف: اپراتور روی **وب / اندروید / ویندوز** از داخل حسابیکس تماس بگیرد و جواب دهد، بدون Zoiper/MicroSIP، حتی وقتی PBX کاملاً پشت فایروال است.

---

## ۱. مسئله، هدف و محدودیت‌ها

### ۱.۱ مسئله

1. سازمان‌ها نمی‌خواهند پورت SIP/WSS/RTP سانترال را به اینترنت باز کنند.
2. اپراتورهای دورکار / شعب / وب‌اپ نمی‌توانند مستقیم به PBX برسند.
3. الگوی فعلی Connector (فقط خروجی HTTPS) برای CTI عالی است، ولی برای صوت هنوز کانالی نیست.
4. وعدهٔ «نمونه اولیه» قابل قبول نیست؛ باید کیفیت و پایداری مرکز تماس سازمانی باشد.

### ۱.۲ هدف محصولی

- Softphone حرفه‌ای داخل حسابیکس
- کاهش نرم‌افزار جانبی
- کار روی Web + Android + Windows
- یکپارچگی کامل با Pop / تاریخچه / گزارش / ضبط / Live Dashboard
- دو مسیر اتصال رسانه (Relay پیش‌فرض، Direct اختیاری)
- بدون وابستگی به SDK پولی یا لایسنس تجاری VoIP

### ۱.۳ خارج از محدوده (این نسخه)

- جایگزینی Issabel/IVR builder
- تماس ویدیویی سازمانی (فاز بعدی اختیاری)
- Whisper/Barge سرپرست (بک‌لاگ پس از هسته)
- ذخیرهٔ ابری اجباری همهٔ ضبط‌ها (همان سیاست فعلی لینک/آپلود اختیاری)
- پشتیبانی PBX غیر Asterisk-family

### ۱.۴ فرضیات عملیاتی ایران

- PBX معمولاً فقط خروجی HTTPS دارد.
- کیفیت لینک شعب متغیر است → نیاز به jitter buffer، reconnect، و مانیتور کیفیت.
- گواهی TLS معتبر برای لبه حسابیکس در دسترس است؛ برای Direct روی PBX ممکن است گواهی داخلی باشد.
- بسیاری مشتریان Issabel 4/5 با Asterisk 13–18 دارند → باید مسیر صوت با قابلیت‌های رایج Asterisk سازگار باشد و fallback داشته باشد.

---

## ۲. اصول معماری (قفل‌شده)

1. **صدا از API کسب‌وکار حسابیکس عبور داده نمی‌شود به‌صورت RTP خام روی REST**؛ از **سرویس لبه رسانه** و تونل دوطرفه استفاده می‌شود.
2. **کنترل تماس و CRM از مسیر CTI فعلی** می‌ماند؛ Softphone فقط endpoint رسانه و UX اپراتور است.
3. **Connector هرگز پورت ورودی اینترنت لازم ندارد** (در حالت Relay).
4. **Asterisk روی localhost** با Connector حرف می‌زند (AudioSocket / ARI ExternalMedia / Local SIP).
5. **Credential دائم SIP در کلاینت ذخیره نمی‌شود** (مگر حالت Direct با سیاست صریح ادمین).
6. **یک Engine Abstraction در Flutter** هر دو حالت Relay و Direct را پشت یک API واحد UI می‌گذارد.
7. **چندمستأجری سخت:** هر سشن رسانه به `business_id + pbx_id + user_id + extension` قفل است.
8. **فقط OSS رایگان** در مسیر بحرانی صوت/سیگنالینگ.

---

## ۳. دو حالت رسانه + یک حالت Desk

### ۳.۱ جدول حالت‌ها

| کد حالت | نام | چه زمانی | نیاز شبکه به PBX از کلاینت | نیاز تنظیم روی PBX |
|---------|-----|----------|------------------------------|---------------------|
| `relay` | رله از طریق افزونه | **پیش‌فرض سازمانی** | فقط به حسابیکس (HTTPS/WSS) | Connector Media Worker + dialplan/AudioSocket |
| `direct` | رجیستر مستقیم WebRTC/PJSIP | اختیاری اگر ادمین فعال کند | دسترسی به WSS/SIP PBX (LAN/VPN/پورت باز) | endpoint PJSIP با `webrtc=yes` + WSS |
| `desk` | تلفن رومیزی / Softphone خارجی | مثل امروز | — | داخلی SIP موجود + Click-to-Call AMI |

هر `telephony_user_extensions` فیلد جدید می‌گیرد:

```text
endpoint_mode: relay | direct | desk
preferred_mode: ...
allow_mode_fallback: bool
```

روی PBX هم:

```text
pbx.settings.softphone = {
  "relay_enabled": true,
  "direct_enabled": false,
  "media_codec_prefs": ["opus", "ulaw", "alaw"],
  "max_concurrent_softphone_sessions": 50
}
```

### ۳.۲ انتخاب حالت در عمل

```
اگر endpoint_mode=relay → همیشه Relay
اگر endpoint_mode=direct → تلاش Direct؛ اگر fail و allow_fallback → Relay
اگر endpoint_mode=desk → Originate مثل امروز (بدون media engine)
```

UI باید حالت فعال و دلیل fallback را شفاف نشان دهد.

---

## ۴. معماری هدف

### ۴.۱ نمای کلی حالت Relay (پیش‌فرض)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Flutter Softphone (Web / Android / Windows)                              │
│  UI: Phone Bar · Dialer · In-call controls · Device picker               │
│  Engine: flutter_webrtc + SoftphoneSessionController                     │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ 1) REST: create softphone session
                                │ 2) WSS signaling (Hesabix)
                                │ 3) WebRTC media (DTLS-SRTP) → Media Edge
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Hesabix Cloud                                                            │
│  API (FastAPI): session/auth/ACL/CRM/CTI                                 │
│  Media Edge Service (OSS): WebRTC termination + session broker           │
│  coturn (STUN/TURN) برای کلاینت ↔ Media Edge                             │
│  Connector Media Hub: تونل‌های خروجی پایدار از Connectorها               │
└───────────────────────────────▲──────────────────────────────────────────┘
                                │ Outbound WSS/gRPC-Web از PBX به Cloud
                                │ (بدون پورت ورودی روی Issabel)
┌───────────────────────────────┴──────────────────────────────────────────┐
│ Hesabix Telephony Connector (+ Media Worker) روی Issabel                 │
│  AMI (موجود) + Media Bridge + AudioSocket/ARI client                     │
└───────────────────────────────▲──────────────────────────────────────────┘
                                │ فقط localhost / شبکه داخلی PBX
┌───────────────────────────────┴──────────────────────────────────────────┐
│ Asterisk / Issabel                                                       │
│  صف‌ها، ترانک‌ها، داخلی‌های رومیزی، MixMonitor، CDR                        │
│  کانال صوتی Softphone: AudioSocket یا ExternalMedia یا PJSIP local       │
└──────────────────────────────────────────────────────────────────────────┘
```

### ۴.۲ نمای حالت Direct (اختیاری)

```
Flutter (sip_ua + flutter_webrtc)
    │ SIP over WSS + WebRTC
    ▼
Issabel PJSIP WebRTC endpoint (LAN/VPN/exposed WSS)
    │
    ▼ AMI events همچنان از Connector به Hesabix برای CRM/Pop
```

در Direct، حسابیکس همچنان CTI را نگه می‌دارد؛ فقط پای رسانه مستقیم به PBX است.

### ۴.۳ چرا این طرح با فایروال سازمانی سازگار است؟

- کلاینت **هرگز** به IP سانترال وصل نمی‌شود (در Relay).
- سانترال **فقط خروجی** به `api/media` حسابیکس می‌زند — همان فلسفهٔ Connector فعلی.
- واحد امنیت شبکه معمولاً این الگو را می‌پذیرد (مشابه ایمیل بریج/وب‌هوک).

---

## ۵. پشته ابزار OSS (بدون لایسنس تجاری)

همه موارد زیر رایگان/متن‌باز هستند و وابستگی لایسنس runtime ندارند.

### ۵.۱ کلاینت (Flutter)

| جزء | ابزار | مجوز تقریبی | نقش |
|-----|--------|-------------|-----|
| WebRTC | `flutter_webrtc` | BSD-like | میکروفون، کدک، PeerConnection |
| سیگنالینگ Relay | کد اختصاصی حسابیکس روی WS موجود/جدید | — | offer/answer/ICE/candidate |
| Softphone Direct | `sip_ua` (بر پایه JsSIP port) | MIT | فقط وقتی `direct` فعال است |
| پخش ضبط (موجود) | `flutter_sound` | — | جدا از تماس زنده |

**نکته:** در Relay از `sip_ua` استفاده **نمی‌شود**؛ چون کلاینت SIP به PBX رجیستر نمی‌کند. سیگنالینگ نرم‌افزاری حسابیکس است.

### ۵.۲ ابر حسابیکس

| جزء | ابزار پیشنهادی | مجوز | نقش | وضعیت |
|-----|------------------|------|-----|--------|
| Media Edge (R1) | Media Hub in-process + WSS PCM | — | ختم سشن کلاینت + پل به تونل | ✅ پیاده |
| ارتقا کیفیت (R3) | **aiortc** یا **Janus** | BSD/GPL | WebRTC/Opus اختیاری | ⏳ |
| TURN/STUN | **coturn** | BSD | عبور NAT کلاینت | ⏳ (ICE config آماده) |
| کنترل‌پلین | FastAPI موجود | — | صدور سشن، ACL | ✅ |
| صف/وضعیت | حافظه نود + جدول سشن | — | presence سشن‌های media | ✅ پایه |

### ۵.۳ Connector روی PBX

| جزء | ابزار | نقش |
|-----|--------|-----|
| کنترل | AMI موجود (pure Python) | originate/hangup/transfer/events |
| پل رسانه | ماژول جدید Python در Connector | تبادل فریم صوت با Cloud + Asterisk |
| اتصال به Asterisk (ترجیحی) | **Asterisk AudioSocket** | صوت دوطرفه TCP به اپ خارجی — بدون WebRTC روی PBX |
| اتصال جایگزین | **ARI ExternalMedia** | اگر AudioSocket در نسخه Asterisk نباشد |
| اتصال جایگزین ۲ | PJSIP endpoint روی `127.0.0.1` | فقط localhost؛ باز هم بدون expose اینترنت |

### ۵.۴ صریحاً ممنوع در این طرح

- Siprix / تجاری‌های دارای لایسنس runtime
- سرویس‌های ابری پولی VoIP به‌عنوان مسیر اجباری
- عبور RTP از سرور اپلیکیشن بدون جداسازی Media Edge
- ذخیره رمز SIP ماندگار در LocalStorage مرورگر بدون سیاست Direct

---

## ۶. مسیر صوت و سیگنالینگ — جزئیات Relay

### ۶.۱ پروتکل‌ها

| بخش | پروتکل | رمزنگاری |
|-----|--------|-----------|
| کلاینت ↔ API | HTTPS | TLS |
| کلاینت ↔ Signaling | WSS | TLS |
| کلاینت ↔ Media Edge | WebRTC (ICE/DTLS/SRTP) | DTLS-SRTP |
| Media Edge ↔ Connector | WSS یا HTTP/2 bidirectional stream روی تونل خروجی | TLS + توکن Connector |
| Connector ↔ Asterisk | AudioSocket TCP یا ARI + RTP localhost | شبکه محلی؛ ترجیحاً bind روی 127.0.0.1 |
| کنترل CTI | AMI + HTTPS webhook/poll موجود | مثل امروز |

### ۶.۲ کدک

ترتیب ترجیح:

1. **Opus** بین کلاینت و Media Edge (WebRTC)
2. در لبه‌ی Connector تبدیل به **slin16 / ulaw / alaw** مطابق کانال Asterisk
3. ترجیح Opus تا PBX فقط اگر کانال/ترانک پشتیبانی کند؛ در غیر این صورت ترنسکود در Connector Media Worker

بودجهٔ کیفیت فاز سازمانی:

- هدف عملیاتی: مکالمه قابل قبول مرکز تماس روی ADSL متوسط
- متریک: RTT، jitter، loss، bitrate، reconnect count
- UI اپراتور: نشانگر کیفیت ساده (خوب/متوسط/ضعیف)

### ۶.۳ مدل سشن

موجودیت جدید پیشنهادی: `telephony_softphone_sessions`

| فیلد | توضیح |
|------|--------|
| id | UUID سشن |
| business_id / pbx_id / user_id | قفل چندمستأجری |
| extension | داخلی منطقی اپراتور |
| mode | `relay` \| `direct` |
| state | `creating` \| `registered` \| `ringing` \| `in_call` \| `ended` \| `failed` |
| media_edge_node | کدام نود media |
| connector_tunnel_id | شناسه تونل |
| call_id | FK به `telephony_calls` وقتی تماس فعال است |
| ice_policy / turn_used | برای دیباگ |
| created_at / expires_at / ended_at | TTL سشن |
| last_quality_json | نمونه متریک |

سشن رجیستر Softphone ≠ تماس. اپراتور می‌تواند آنلاین باشد بدون تماس فعال.

### ۶.۴ جریان رجیستر Relay (آنلاین شدن اپراتور)

```
1. کاربر وارد کسب‌وکار می‌شود؛ Phone Bar فعال است؛ endpoint_mode=relay
2. Flutter → POST /telephony/business/{id}/softphone/sessions
3. API بررسی: لایسنس افزونه، permission، mapping داخلی، pbx online، relay_enabled
4. API به Media Hub می‌گوید: برای این pbx تونل Connector زنده است؟
5. اگر تونل offline → خطا با پیام فارسی واضح + راهنمای Connector
6. API سشن می‌سازد و ticket کوتاه‌عمر media برمی‌گرداند
7. Flutter به Media Edge با WebRTC connect می‌شود (data/keepalive + آماده‌باش صوت)
8. Connector مطلع می‌شود: agent X online روی extension 102
9. AMI/Presence: داخلی softphone به‌عنوان در دسترس علامت می‌خورد (با مکانیزم تعریف‌شده)
10. UI: وضعیت «آماده پاسخگویی»
```

**مهم:** در Relay، «رجیستر» یعنی حضور روی Media Hub/Connector، نه REGISTER سیپ به Asterisk عمومی.

### ۶.۵ جریان تماس ورودی (Relay)

```
1. تماس وارد Issabel → صف/داخلی
2. Dialplan برای اپراتورهای Softphone-Relay به‌جای حلقه SIP خارجی،
   کانال را به AudioSocket(uuid) / ExternalMedia می‌برد
   یا از طریق Local channel کنترل‌شده توسط Connector
3. AMI event → Connector → Hesabix (مثل امروز) → Screen Pop
4. همزمان Media Hub: سشن صوت برای user را ring می‌کند
5. Flutter ringtone + دکمه Answer
6. Answer → signaling به Media Edge → Connector پل را کامل می‌کند
7. صوت دوطرفه برقرار
8. state machine تماس موجود (ringing→answered→completed) بدون شکست CRM
```

### ۶.۶ جریان تماس خروجی (Relay)

```
1. اپراتور از Dialer / PhoneLink شماره می‌گیرد
2. اگر mode=relay: دیگر AMI Originate به «گوشی SIP اپراتور» نمی‌رود
3. به‌جای آن:
   a) سشن media اپراتور باید online باشد
   b) دستور به Connector: Originate سمت مقصد (ترانک/شماره) و Bridge به AudioSocket سشن اپراتور
4. Flutter حالت dialing/ringing/in_call را از signaling + CTI events می‌گیرد
5. telephony_calls با direction=outbound ثبت می‌شود
```

این دقیقاً درد Click-to-Call فعلی (وابستگی به گوشی جانبی) را حذف می‌کند.

### ۶.۷ Hold / Mute / DTMF / Transfer

| عمل | کجا اجرا شود |
|-----|----------------|
| Mute | کلاینت (قطع track میکروفون) + اطلاع به سرور برای audit |
| Hold | ترجیحاً Asterisk hold از طریق دستور Connector (موسیقی انتظار PBX) |
| DTMF | از کلاینت به‌صورت event به Connector → `Play DTMF` روی کانال Asterisk |
| Blind Transfer | دستور AMI/ARI موجود از UI |
| Hangup | هم media close هم AMI hangup؛ idempotent |

### ۶.۸ قطع شبکه و بازیابی

- قطع کوتاه کلاینت (< N ثانیه): تلاش ICE restart / re-offer؛ تماس را فوراً hangup نکن
- قطع طولانی: وضعیت `reconnecting`؛ بعد از آستانه → hangup تمیز + ثبت `failed/cancelled` با علت
- قطع تونل Connector: همه سشن‌های Softphone آن PBX → `degraded`؛ UI قرمز؛ Desk mode اگر مجاز باشد پیشنهاد شود
- Heartbeat تونل رسانه جدا از heartbeat CTI (هر ۲–۵ ثانیه)

---

## ۷. اتصال Connector به Asterisk بدون expose کردن PJSIP

### ۷.۱ گزینه A — AudioSocket (ترجیحی)

- Asterisk اپلیکیشن `AudioSocket` دارد (نسخه‌های جدیدتر).
- Connector روی `127.0.0.1:PORT` گوش می‌دهد.
- Dialplan نمونهٔ مفهومی:

```asterisk
[hesabix-softphone-relay]
exten => _X.,1,NoOp(Hesabix Softphone Relay)
 same => n,Set(HSX_UUID=${UNIQUEID})
 same => n,AudioSocket(127.0.0.1:9092,${HSX_UUID})
 same => n,Hangup()
```

- مزیت: بدون WebRTC روی PBX، بدون پورت اینترنت، پیاده‌سازی تمیز برای Agent خارجی.
- ریسک: باید نسخه Asterisk مشتری پشتیبانی کند؛ در غیر این صورت fallback.

### ۷.۲ گزینه B — ARI ExternalMedia

- Connector به ARI محلی وصل می‌شود (فقط LAN/localhost).
- کانال ExternalMedia می‌سازد و RTP را خودش terminate می‌کند.
- مزیت: کنترل برنامه‌ای قوی‌تر برای Bridge/Hold.
- ریسک: پیکربندی ARI و نسخه؛ کمی پیچیده‌تر از AudioSocket.

### ۷.۳ گزینه C — PJSIP localhost-only

- یک endpoint محلی مثل `hsx-media-102` فقط روی `127.0.0.1`.
- Connector با استک SIP سبک OSS (مثلاً بخشی از pjproject/aiortc-sip یا پیاده‌سازی محدود) رجیستر محلی می‌کند.
- مزیت: سازگاری بالا با Issabel سنتی.
- ریسک: پیچیدگی SIP در Connector؛ فقط اگر A/B نشد.

### ۷.۴ استراتژی سازگاری Issabel

ویزارد `hesabix-pbx softphone-relay-setup`:

1. تشخیص نسخه Asterisk
2. انتخاب خودکار backend صوت: AudioSocket → ARI → Local PJSIP
3. نوشتن/پیشنهاد snippet دیال‌پلن
4. تست لوپ‌بک صوت ۳۰ ثانیه‌ای
5. گزارش health به حسابیکس

**نتیجه برای مشتری:** «نیازی به باز کردن PJSIP/WebRTC به اینترنت نیست.»  
اگر خواست Direct را جداگانه فعال می‌کند.

---

## ۸. حالت Direct (اختیاری، بدون اجبار)

برای سازمانی که VPN دارد یا WSS را عمداً باز می‌کند:

### ۸.۱ پیش‌نیاز PBX

- Transport WSS (مثلاً 8089) با TLS
- endpoint PJSIP با DTLS-SRTP / webrtc
- STUN/TURN مناسب شبکه همان سازمان

### ۸.۲ کلاینت

- `sip_ua` + `flutter_webrtc`
- credential از API با TTL یا از تنظیم ادمین (ترجیح TTL یک‌بارمصرف اگر PBX از طریق Connector provision شود)

### ۸.۳ CTI

- همچنان Connector رویداد AMI را برای Pop/CDR می‌فرستد
- باید از دوباره‌شماری تماس (یک بار از SIP client و یک بار از AMI) جلوگیری شود — کلید `linkedid/uniqueid`

### ۸.۴ امنیت Direct

- پیش‌فرض خاموش
- هشدار صریح در UI تنظیمات: «پورت PBX از بیرون در دسترس خواهد بود مگر پشت VPN»
- توصیه محصولی: Relay برای اینترنت؛ Direct برای LAN/VPN

---

## ۹. مدل داده و API (افزوده‌ها)

### ۹.۱ جداول/فیلدهای جدید

- `telephony_softphone_sessions` (بالا)
- `telephony_user_extensions.endpoint_mode`
- `telephony_user_extensions.direct_sip_user` (nullable)
- `telephony_pbx_connections.settings.softphone` JSON
- `telephony_commands.command_type` گسترش:  
  `softphone_bridge_in` | `softphone_bridge_out` | `softphone_dtmf` | `softphone_set_presence`
- `telephony_metric_counter` متریک‌های media: `softphone_sessions_active`, `media_tunnel_up`, `opus_transcode_errors`, ...

### ۹.۲ APIهای اصلی (پیشنهادی)

**اپراتور (JWT کسب‌وکار):**

- `POST /api/v1/telephony/business/{id}/softphone/sessions` — ایجاد/تمدید سشن
- `POST /api/v1/telephony/business/{id}/softphone/sessions/{sid}/heartbeat`
- `DELETE /api/v1/telephony/business/{id}/softphone/sessions/{sid}` — unregister
- `POST /api/v1/telephony/business/{id}/softphone/calls` — شروع خروجی در حالت relay
- `POST /api/v1/telephony/business/{id}/softphone/calls/{call_id}/answer`
- `POST /api/v1/telephony/business/{id}/softphone/calls/{call_id}/dtmf`
- `GET  /api/v1/telephony/business/{id}/softphone/devices-config` — iceServers/turn موقت
- `GET  /api/v1/telephony/business/{id}/softphone/health`

**Connector (token موجود + قابلیت media):**

- `GET  /api/v1/telephony/connector/media/tunnel` (Upgrade WSS) یا endpoint جدا روی Media Hub
- `POST /api/v1/telephony/connector/media/events`
- `POST /api/v1/telephony/connector/media/quality`

**ادمین کسب‌وکار:**

- فعال/غیرفعال Relay/Direct
- سقف سشن همزمان
- اجبار mode برای همه کاربران یا per-user

### ۹.۳ مجوزها

جدید:

- `telephony.softphone` — استفاده اپراتور
- `telephony.softphone_manage` — تنظیمات mode/provision
- `telephony.softphone_quality` — دیدن متریک کیفیت تیم (سرپرست)

موجودها (`click_to_call`, `control_calls`, ...) حفظ می‌شوند.

### ۹.۴ رویدادهای WS

علاوه بر `telephony.*` فعلی:

- `telephony.softphone.registered`
- `telephony.softphone.unregistered`
- `telephony.softphone.incoming_media`
- `telephony.softphone.reconnecting`
- `telephony.softphone.quality_changed`
- `telephony.softphone.tunnel_down`

---

## ۱۰. UX سازمانی (وب / اندروید / ویندوز)

### ۱۰.۱ Phone Bar (ارتقاء)

وضعیت‌ها:

- قطع از مرکز تلفن
- Connector آنلاین / تونل رسانه قطع
- Softphone آماده‌باش
- در حال زنگ
- در حال مکالمه (+ تایمر)
- در حال اتصال مجدد

دکمه‌ها: شماره‌گیر، پاسخ، قطع، mute، hold، انتقال، وضعیت هدست.

### ۱۰.۲ صفحه Softphone (جایگزین اسکفولد فعلی)

- نمایش داخلی و mode فعال
- تست میکروفون/بلندگو قبل از شیفت
- انتخاب دستگاه صوت (Desktop/Web)
- لاگ تشخیصی جمع‌وجور برای پشتیبانی (قابل کپی)

### ۱۰.۳ الزامات پلتفرم

| پلتفرم | الزام سازمانی |
|--------|----------------|
| Web | HTTPS، permission میکروفون، جلوگیری از double-tab register، هشدار بستن تب هنگام مکالمه |
| Android | Foreground Service هنگام تماس، اعلان Incoming، قفل صفحه، بازیابی پس از تعویض شبکه |
| Windows | کار در tray/minimize بدون unregister، hotkey پاسخ/قطع، انتخاب device پایدار بعد از sleep |

### ۱۰.۴ یکپارچگی CRM

بدون تغییر فلسفه:

- Screen Pop روی ringing
- Post-call sheet
- ایجاد Person/Lead
- لینک به `crm_activities`
- گزارش‌ها همان `telephony_calls`

تفاوت فقط منبع رسانه است، نه مدل کسب‌وکار.

---

## ۱۱. امنیت، حریم خصوصی، انطباق

1. توکن Connector و ticket مدیا کوتاه‌عمر؛ چرخش‌پذیر
2. Media Edge جدا از API داده؛ حداقل داده CRM روی مسیر صوت نباشد
3. Audit: شروع سشن، پاسخ، گوش‌دادن ضبط، انتقال، تغییر mode
4. محدودیت نرخ ایجاد سشن per user
5. انکار سشن اگر mapping داخلی نداشته باشد
6. در Relay هیچ پورت PBX به اینترنت publish نشود (چک‌لیست نصب)
7. ضبط همچنان با permission `listen_recordings`
8. جداسازی کامل tenant در broker تونل‌ها
9. عدم نگهداری صوت مکالمه روی دیسک Media Edge مگر برای jitter کوتاه؛ SoT ضبط = PBX/سیاست فعلی
10. هشدار حقوقی به مشتری: مسئولیت ضبط قانونی با پیکربندی PBX آن‌هاست (مثل سند قبلی)

---

## ۱۲. عملیات، نصب، مشاهده‌پذیری

### ۱۲.۱ ویزارد نصب Relay

گام‌ها در UI حسابیکس + CLI Connector:

1. فعال‌سازی افزونه و ساخت PBX (موجود)
2. نصب/آپدیت Connector (موجود)
3. `hesabix-pbx softphone-relay-setup`
4. تست تونل رسانه (سبز/قرمز)
5. تست لوپ‌بک صوت با کاربر آزمایشی
6. انتخاب mode پیش‌فرض کاربران
7. آموزش ۳۰ ثانیه‌ای اپراتور (میکروفون/پاسخ)

### ۱۲.۲ متریک‌های سلامت (حداقلی)

- تعداد تونل‌های media online
- سشن‌های softphone فعال per PBX
- نرخ شکست answer
- میانگین زمان setup تماس (ring→media connected)
- درصد استفاده TURN
- خطاهای ترنسکود
- نسخه Connector / قابلیت AudioSocket|ARI

### ۱۲.۳ ظرفیت‌سنجی اولیه

فرض فاز ۱:

- ۵۰ سشن همزمان softphone per PBX متوسط
- Media Edge افقی‌پذیر (چند نود پشت LB)
- یک Connector process با workerهای async برای RTP/frames

آستانه هشدار: CPU Connector > ۷۰٪ پایدار یا loss > ۵٪ در ۱ دقیقه.

---

## ۱۳. فازبندی اجرایی دقیق

### فاز R0 — Discovery و Lab (۲ هفته)

**هدف:** اثبات کیفیت روی Issabel واقعی پشت فایروال.

**وضعیت:** در حال اجرا — زیرساخت PoC در مخزن آماده؛ UAT روی Issabel واقعی باقی است.

کارها:

- [x] قرارداد معماری Relay (تونل خروجی + AudioSocket localhost)
- [x] پروتکل فریم رسانه `HSXM` + پروفایل `pcm_ws_v1`
- [x] اسکلت Media Hub در API + تونل WSS Connector
- [x] نمونه دیال‌پلن `hesabix-softphone-relay.conf.sample`
- [ ] برپایی lab: Issabel بدون پورت ورودی + حسابیکس staging (محیط مشتری/ops)
- [ ] اندازه‌گیری RTT/loss/CPU روی مکالمه واقعی ۵ دقیقه‌ای
- [x] تصمیم backend صوت Asterisk برای R1: **AudioSocket** (fallback ARI/Local بعداً)

پذیرش:

- [ ] مکالمه ۲ طرفه پایدار ۵ دقیقه پشت فایروال کامل
- [x] طراحی بدون نیاز به پورت ورودی PBX (معماری تأیید شد؛ تأیید nmap روی lab باقی است)
- [x] Screen Pop همزمان با ringing (مسیر CTI موجود حفظ شد)

### فاز R1 — هسته Softphone Relay (۵ هفته)

**وضعیت:** ✅ کد کامل — UAT روی Issabel واقعی باقی است.

- [x] مدل داده سشن (`telephony_softphone_sessions`) + `endpoint_mode` روی user_extensions + migration
- [x] API سشن/سلامت/خروجی/پاسخ/DTMF + permissions UI
- [x] Media Hub MVP (in-process) + WS کلاینت و تونل Connector
- [x] Media Worker در Connector (AudioSocket + MediaTunnel + دستورات softphone_*)
- [x] Engine Flutter + جایگزینی صفحه اسکفولد Softphone
- [x] Answer / Hangup / Mute / Dial outbound (مسیر کنترل)
- [x] یکپارچگی با `telephony_calls` برای خروجی relay
- [x] پخش و ضبط میکروفون واقعی (`softphone_pcm_media` — flutter_sound روی IO، WebAudio+VoiceWebCapture روی Web @ 8kHz)
- [x] UI تنظیمات: ویرایش `endpoint_mode` / fallback / Softphone PBX settings + ویزارد راه‌اندازی Relay
- [x] Phone Bar یکپارچه با SoftphoneEngineStore (پاسخ/Mute/قطع/وضعیت)
- [x] Click-to-Call وقتی Softphone آنلاین است مسیر Relay را ترجیح می‌دهد
- [ ] UAT ورودی/خروجی کامل روی Web با Issabel واقعی (محیط ops)

پذیرش:

- [ ] ورودی و خروجی کامل بدون Softphone خارجی روی Web *(منتظر lab Issabel)*
- [x] Android و Windows مسیر مشترک آماده (PCM via flutter_sound؛ تست دستگاه در UAT)
- [x] desk mode Intact (Click-to-Call و originate حفظ شد)

#### فایل‌های کلیدی اضافه‌شده/تغییریافته در R1

- `hesabixAPI/migrations/versions/20260806_000003_telephony_softphone_media_relay.py`
- `hesabixAPI/app/services/telephony/media_hub.py`
- `hesabixAPI/app/services/telephony/softphone_service.py`
- `hesabixAPI/adapters/api/v1/telephony_softphone_ws.py`
- `hesabixAPI/adapters/api/v1/telephony.py` (endpointهای softphone)
- `extraScripts/HesabixTelephonyConnector/app/media_audiosocket.py`
- `extraScripts/HesabixTelephonyConnector/app/media_tunnel.py`
- `extraScripts/HesabixTelephonyConnector/app/main.py`
- `hesabixUI/.../softphone_engine.dart` + `softphone_ws_client_*.dart` + `softphone_pcm_media_*.dart`
- `hesabixUI/.../telephony_softphone_page.dart`
- `hesabixUI/.../telephony_hub_page.dart` (تنظیمات Softphone / endpoint_mode)
- `hesabixUI/.../telephony_phone_bar.dart`
- `hesabixUI/.../telephony_session_controller.dart` (اولویت Relay در Click-to-Call)

### فاز R2 — CTI Sync و کنترل‌های تماس (۳ هفته)

- Hold/DTMF/Transfer هماهنگ با AMI
- Presence واقعی softphone در Live Dashboard
- حذف تداخل Originate با Relay
- Fallback desk/direct طبق تنظیم

پذیرش:

- [ ] Transfer از UI در Relay
- [ ] داشبورد وضعیت idle/busy صحیح
- [ ] عدم ثبت دوبل CDR

### فاز R3 — سخت‌سازی پلتفرم و شبکه (۴ هفته)

- coturn تولید
- reconnect/ICE restart
- Android foreground + notification
- Windows tray/device
- Web multi-tab guard
- متریک کیفیت در UI و ops

پذیرش:

- [ ] تعویض WiFi↔۴G بدون hangup فوری (در آستانه تعریف‌شده)
- [ ] minimize ویندوز مکالمه را نکشد
- [ ] اعلان Incoming اندروید وقتی اپ پشت است

### فاز R4 — Direct اختیاری + عملیات فروش (۳ هفته)

- فعال‌سازی `direct` با `sip_ua`
- ویزارد و هشدار امنیتی
- مستندات فارسی کامل Relay vs Direct vs Desk
- UAT با ۲–۳ مشتری واقعی (یکی کاملاً قفل‌فایروال)

پذیرش:

- [ ] مشتری قفل‌فایروال فقط با Relay کار کند
- [ ] مشتری VPN بتواند Direct را انتخاب کند
- [ ] تکنسین Issabel با مستند، بدون تیم توسعه، Relay را بالا بیاورد

### فاز R5 — پیشرفته (بک‌لاگ)

- Attended transfer پیشرفته / کنفرانس سه‌طرفه
- Whisper/Barge (ARI)
- ضبط سمت سرپرست زنده
- Janus به‌جای aiortc اگر مقیاس ایجاب کرد
- iOS Push/CallKit کامل

**جمع تا نسخه قابل فروش سازمانی Relay:** حدود ۱۶–۱۸ هفته با تیم متمرکز.

---

## ۱۴. سناریوهای پذیرش Must-pass (سازمانی)

1. PBX بدون هیچ پورت ورودی: اپراتور وب پاسخ می‌دهد و صحبت می‌کند.
2. همان روی اندروید و ویندوز.
3. خروجی از پروفیل مشتری بدون Zoiper.
4. Desk-phone همزمان برای کاربر دیگر همان کسب‌وکار کار کند.
5. قطع اینترنت شعبه: UI وضعیت تونل را نشان دهد؛ پس از وصل، بازیابی سشن.
6. تعویض کسب‌وکار: unregister کامل و register با داخلی جدید.
7. دو تب مرورگر: جلوگیری از رجیستر دوبل مخرب.
8. Transfer به داخلی رومیزی و ادامه تاریخچه یکسان.
9. Direct روی lab VPN کار کند بدون شکستن Relay.
10. کاربر بدون permission softphone فقط desk/click-to-call ببیند.
11. حمله token نامعتبر به تونل media رد شود.
12. کیفیت روی ADSL متوسط «قابل بهره‌برداری شیفت ۸ ساعته» در UAT انسانی.

---

## ۱۵. ریسک‌ها و کاهش

| ریسک | اثر | کاهش |
|------|-----|------|
| تأخیر اضافه در Relay (یک hop ابری) | کیفیت پایین‌تر از LAN Direct | Opus، نود media نزدیک، مانیتور، گزینه Direct برای LAN |
| CPU ترنسکود روی Connector | محدودیت ظرفیت | کدک مناسب، worker جدا، سقف سشن |
| نبود AudioSocket در Asterisk قدیمی | بلاک پیاده‌سازی | fallback ARI / Local PJSIP |
| پیچیدگی همزمان CTI + Media | باگ حالت تماس | state machine واحد، تست ماتریسی |
| antimalware/firewall مشتری روی WSS خروجی | تونل بالا نیاید | پورت 443، دامنه رسمی، راهنمای whitelist |
| انتظار کاربر از کیفیت تلفن رومیزی | نارضایتی | هدست اجباری در آموزش، تست دستگاه، شاخص کیفیت |
| دو مسیر Direct/Relay | هزینه نگهداری | Abstraction Engine + یک UI |

---

## ۱۶. تصمیم‌های محصولی که باید قبل از کدنویسی قفل شوند

| # | موضوع | پیشنهاد سند |
|---|--------|-------------|
| 1 | پیش‌فرض همه مشتریان جدید | `relay` |
| 2 | آیا Direct در نسخه ۱ فروش باشد؟ | بله، ولی خاموش و پشت flag ادمین |
| 3 | Media Edge جدا از API یا داخل‌مونو | سرویس جدا `hesabix-media` از روز اول |
| 4 | هزینه زیرساخت TURN/Media | جزو هزینه افزونه/پلن؛ نه لایسنس شخص ثالث |
| 5 | سقف سشن همزمان پیش‌فرض | ۵۰ per PBX قابل تنظیم |
| 6 | آیا Click-to-Call برای کاربران Relay مخفی شود؟ | بله در UI؛ API desk فقط اگر mode=desk |

---

## ۱۷. معیار «عالی سازمانی» (تعریف Done)

این قابلیت Done است فقط اگر:

1. بدون نرم‌افزار جانبی، شیفت کامل پشتیبانی روی وب یا ویندوز ممکن باشد.
2. مشتری با PBX قفل‌فایروال بتواند فروخته و راه‌اندازی شود.
3. CRM/Pop/گزارش/ضبط با همان کیفیت CTI فعلی کار کند.
4. ابزار مسیر صوت لایسنس تجاری نداشته باشد.
5. حالت Desk و Direct (اختیاری) بدون فروپاشی معماری پشتیبانی شوند.
6. مشاهده‌پذیری کافی برای پشتیبانی سطح ۲ وجود داشته باشد.
7. مستند نصب فارسی توسط تکنسین Issabel مستقل اجرا شود.

---

## ۱۸. جمع‌بندی راهبرد

- **بله، می‌شود صدا را از طریق افزونه/Connector رله کرد** و نیازی به باز بودن PJSIP/WebRTC سانترال به اینترنت نباشد.
- **رجیستر مستقیم** به‌عنوان گزینه برای شبکه‌های باز/VPN باقی می‌ماند.
- **مسیر درست:** WebRTC تا ابر حسابیکس + تونل خروجی Connector + AudioSocket/ARI محلی به Asterisk + حفظ CTI فعلی.
- **پشته پیشنهادی رایگان:** `flutter_webrtc` (+ `sip_ua` فقط برای Direct) · `aiortc` · `coturn` · Asterisk AudioSocket/ARI · Connector Python موجود.

**قدم بعد پس از تأیید این سند:** شکستن فاز R0 به تیکت‌های اجرایی lab و تعیین owner برای Media Edge و Connector Media Worker — بدون شروع پیاده‌سازی محصول تا پایان PoC کیفیت R0.

---

**پایان سند v1.0.0**
