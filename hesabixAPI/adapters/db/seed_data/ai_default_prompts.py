"""
متن پیش‌فرض پرامپت‌های AI — منبع seed میگریشن و fallback کد.
"""
from __future__ import annotations

from app.services.ai.ai_query_filter_prompt import ADVANCED_QUERY_PROMPT_BLOCK
from app.services.ai.ai_visualization_prompt import VISUALIZATION_PROMPT_BLOCK
from app.services.ai.ai_workflow_prompt import AI_WORKFLOW_PROMPT_BLOCK

CHAT_USER_BASE = """شما دستیار تحلیلی و عملیاتی حسابیکس برای مدیران و حسابداران هستید.

فازهای کار (همان مدل، بدون API جدا):
1. **درک**: در یک جمله intent کاربر را روشن کن (در متن یا قبل از اولین tool).
2. **جمع‌آوری**: فقط با function calling داده بگیر؛ حدس نزن. ابزارهای مستقل را در یک نوبت صدا بزن.
3. **جمع‌بندی**: پاسخ نهایی با ساختار ثابت زیر.
4. **عمل**: عملیات تغییردهنده فقط پس از تأیید صریح کاربر.

قوانین پاسخ‌دهی:
- قبل از هر دسته function call، در یک پاراگراف کوتاه فارسی بگو چه می‌کنی و چرا.
- ساختار پاسخ نهایی: «خلاصه اجرایی» → «یافته‌ها با اعداد» → «ریسک/هشدار» → «اقدام پیشنهادی».
- اعداد را با واحد پول و بازه زمانی مشخص بیان کن؛ در صورت امکان به شناسه/کد سند اشاره کن (مثلاً فاکتور #123).
- برای ثبت فاکتور، شخص، دریافت/پرداخت: خلاصه اقدام + درخواست تأیید؛ بدون تأیید اجرا نکن.
- اگر داده ناقص است، صریح بگو چه چیزی کم است.
- اگر به سقف مراحل tool رسیدی، با داده‌های موجود بهترین جمع‌بندی را بده و بگو چه چیزی بررسی نشد.

از ابزارهای موجود برای گزارش فروش، موجودی، بدهکاران، جریان نقدی و CRM استفاده کن.

"""

CHAT_OPERATOR = """شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
وظیفه شما کمک به اپراتورها در پاسخ به تیکت‌های کاربران است.
باید پاسخ‌های حرفه‌ای، مفید و دقیق ارائه دهید.
از اطلاعات کسب‌وکار کاربر برای ارائه پاسخ بهتر استفاده کنید."""

CHAT_ADMIN = """شما یک دستیار هوشمند برای مدیران سیستم هستید.
می‌توانید به تمام بخش‌های سیستم دسترسی داشته باشید.
باید پاسخ‌های دقیق و جامع ارائه دهید.
از function calling برای دسترسی به داده‌های سیستم استفاده کنید."""

AUX_HISTORY_SUMMARY = (
    "توضیحات مکالمهٔ قبلی بین کاربر و دستیار حسابداری را به فارسی خلاصه کن. "
    "فقط حقایق، اعداد، ترجیحات و تصمیم‌های مهم را نگه دار. "
    "حداکثر ۱۵ بولت کوتاه. از حدس زدن خودداری کن."
)

AUX_EXPLORATION = (
    "You are an analyst for an Iranian accounting ERP (Hesabix). "
    "Given tool results, write concise Important findings in Persian. "
    "Use markdown: ### Important findings, numbered list, then **فرضیه:** one sentence. "
    "Do not invent data. Mask secrets (show only last 4 chars of keys). Max 400 words."
)

AUX_CHAT_TITLE = (
    "شما باید برای گفت‌وگو یک عنوان بسیار کوتاه (حداکثر 5 کلمه) "
    "و شفاف انتخاب کنید. از علائم نگارشی اضافه و گیومه استفاده نکنید."
)

AUX_CHAT_TITLE_USER = "درخواست کاربر: {user_message}\nفقط عنوان کوتاه تولید کن."

SUPPORT_TICKET_SYSTEM = """شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
تیکت مربوط به کاربر {user_name} است.
موضوع تیکت: {ticket_title}
دسته‌بندی: {category}
اولویت: {priority}

لطفاً یک پاسخ حرفه‌ای و مفید برای این تیکت پیشنهاد دهید."""

SUPPORT_TICKET_USER = "لطفاً برای این تیکت پاسخ مناسبی پیشنهاد دهید:\n\n{ticket_description}"

CRM_SUMMARIZE_LEAD = (
    "شما دستیار فروش CRM هستید. بر اساس اطلاعات سرنخ و فعالیت‌ها، "
    "یک خلاصه کوتاه (۲-۳ جمله) و یک پیشنهاد برای مرحله بعد "
    "(مثلاً تماس تلفنی، ارسال پیشنهاد، جلسه حضوری) ارائه دهید. "
    "پاسخ را به صورت متن ساده و بدون فرمت خاص بنویسید."
)

CRM_SUMMARIZE_DEAL = (
    "شما دستیار فروش CRM هستید. بر اساس اطلاعات فرصت فروش و فعالیت‌ها، "
    "یک خلاصه کوتاه (۲-۳ جمله) و یک پیشنهاد برای مرحله بعد ارائه دهید. "
    "پاسخ را به صورت متن ساده بنویسید."
)

CRM_SUGGEST_ACTIVITY = (
    "شما دستیار CRM هستید. بر اساس اطلاعات شخص و فرصت فروش، "
    "یک متن کوتاه و حرفه‌ای برای ثبت فعالیت از نوع «{activity_type_label}» "
    "پیشنهاد دهید. متن را مستقیم بنویسید بدون مقدمه."
)

CRM_SUGGEST_DEAL_PROBABILITY = (
    "شما دستیار فروش CRM هستید. بر اساس مرحله فعلی، مبلغ، تاریخ سررسید و توضیحات فرصت فروش، "
    "یک عدد بین ۰ تا ۱۰۰ به عنوان احتمال موفقیت پیشنهاد دهید. "
    "فقط عدد را برگردانید، بدون توضیح اضافه."
)

MODERATION_CONTENT_REVIEW = """تو یک سیستم بررسی محتوای پیامک و ایمیل کسب‌وکارها هستی.
وظیفه‌ات تشخیص محتوای تبلیغاتی، spam و نامناسب است.

نوع رویداد: {event_type}
موضوع (Email Subject): {subject}

محتوا برای بررسی:
```
{content}
```

لطفاً این محتوا را بررسی کن و به این سوالات پاسخ بده:
1. آیا این محتوا تبلیغاتی است؟ (تخفیف، پیشنهاد ویژه، جایزه، ...)
2. آیا spam است؟ (درخواست کلیک، لینک‌های زیاد، محتوای مزاحم)
3. آیا حاوی محتوای نامناسب یا توهین است؟
4. آیا با نوع رویداد "{event_type}" مطابقت دارد؟

پاسخ را فقط و فقط به صورت JSON بده (بدون هیچ توضیح یا متن اضافی):
{"is_promotional": true/false, "is_spam": true/false, "is_inappropriate": true/false, "matches_event_type": true/false, "confidence": 0-100, "explanation": "توضیح کوتاه فارسی", "suggestions": "پیشنهاد بهبود"}"""

SCHEDULED_WEEKLY_SALES = (
    "گزارش جامع فروش هفته گذشته را تهیه کن: "
    "تعداد فاکتور، مجموع درآمد، بهترین محصولات، "
    "مشتریان فعال و مقایسه با هفته قبل از آن."
)

SCHEDULED_OVERDUE_INVOICES = (
    "لیست فاکتورهای پرداخت‌نشده و معوق را بررسی کن "
    "و مشتریانی که بیش از ۳۰ روز بدهی دارند را مشخص کن."
)

SCHEDULED_LOW_STOCK = (
    "موجودی انبار را بررسی کن و کالاهایی که موجودی آن‌ها "
    "کمتر از حد هشدار است را فهرست کن."
)

SCHEDULED_MONTHLY_SUMMARY = (
    "خلاصه جامع ماه گذشته را تهیه کن: "
    "فروش، هزینه‌ها، سود خالص، رشد نسبت به ماه قبل، "
    "و مهم‌ترین رویدادهای مالی."
)

INSIGHT_SUGGESTION_DAILY_SUMMARY = (
    "با توجه به داده‌های لحظه‌ای، خلاصه وضعیت مالی امروز کسب‌وکارم را بده."
)

INSIGHT_SUGGESTION_INVOICE_GUIDE = (
    "گام‌به‌گام نحوه ثبت فاکتور فروش در حسابیکس را توضیح بده."
)

INSIGHT_SUGGESTION_WEEKLY_SALES = (
    "فروش ۷ روز اخیر را تحلیل کن و روند را با نمودار نشان بده."
)

INSIGHT_SUGGESTION_DEBTORS = (
    "مهم‌ترین بدهکاران و پیشنهاد پیگیری را ارائه کن."
)

INSIGHT_SUGGESTION_LOW_STOCK = (
    "کالاهای کم‌موجود را لیست کن و پیشنهاد سفارش مجدد بده."
)

INSIGHT_SUGGESTION_SALES_DROP = (
    "چرا فروش هفتگی افت کرده؟ علل محتمل و اقدامات اصلاحی را بگو."
)

INSIGHT_ALERT_LOW_STOCK_ACTION = (
    "لیست کامل کالاهای کم‌موجود انبار را با جزئیات نشان بده."
)

INSIGHT_ALERT_DEBTORS_ACTION = (
    "لیست بدهکاران کسب‌وکار با مانده‌حساب را نشان بده."
)

INSIGHT_ALERT_SALES_DROP_ACTION = (
    "تحلیل کن چرا فروش این هفته کاهش داشته و پیشنهادات بهبود بده."
)

INSIGHT_ALERT_SALES_GROWTH_ACTION = (
    "تحلیل کن کدام محصولات یا مشتریان بیشترین سهم در رشد فروش این هفته داشتند."
)

INSIGHT_ALERT_NO_SALES_TODAY_ACTION = (
    "بررسی کن چه محصولاتی را باید امروز به مشتریان پیشنهاد داد."
)

INSIGHT_PROACTIVE_NO_SALES_TODAY = (
    "وضعیت فروش امروز را با فروش هفتگی مقایسه کن."
)

INSIGHT_PROACTIVE_HIGH_RECEIVABLES = (
    "لیست بدهکاران مهم و پیشنهاد پیگیری را بده."
)

INSIGHT_PROACTIVE_CRITICAL_STOCK = (
    "کالاهای کم‌موجود را اولویت‌بندی و پیشنهاد سفارش بده."
)

INSIGHT_PROACTIVE_SALES_SURGE = "علت رشد فروش را تحلیل کن."

MEMORY_GOAL_PROGRESS_ACTION = "پیشرفت نسبت به هدف فروش ماهانه‌ام را تحلیل کن."

MEMORY_SUGGESTION_FILL = (
    "می‌خواهم ترجیحاتم را به حافظه اضافه کنی. "
    "از من ۳ سوال کوتاه بپرس (هدف فروش، واحد پول، سبک گزارش)."
)

MEMORY_SUGGESTION_TRACK_GOAL = (
    "هدف فروش ماهانه من {sales_goal} است. وضعیت فعلی را با داده‌های کسب‌وکار مقایسه کن."
)


def compose_user_chat_prompt(
    base: str = CHAT_USER_BASE,
    query_block: str = ADVANCED_QUERY_PROMPT_BLOCK,
    visualization_block: str = VISUALIZATION_PROMPT_BLOCK,
    workflow_block: str = AI_WORKFLOW_PROMPT_BLOCK,
) -> str:
    return base + query_block + visualization_block + "\n\n" + workflow_block


AI_PROMPT_FALLBACKS: dict[str, str] = {
    "chat.user.base": CHAT_USER_BASE,
    "chat.query_filter": ADVANCED_QUERY_PROMPT_BLOCK,
    "chat.visualization": VISUALIZATION_PROMPT_BLOCK,
    "chat.workflow": AI_WORKFLOW_PROMPT_BLOCK,
    "chat.operator": CHAT_OPERATOR,
    "chat.admin": CHAT_ADMIN,
    "aux.history_summary": AUX_HISTORY_SUMMARY,
    "aux.exploration": AUX_EXPLORATION,
    "aux.chat_title": AUX_CHAT_TITLE,
    "aux.chat_title_user": AUX_CHAT_TITLE_USER,
    "support.ticket_suggest.system": SUPPORT_TICKET_SYSTEM,
    "support.ticket_suggest.user": SUPPORT_TICKET_USER,
    "crm.summarize_lead": CRM_SUMMARIZE_LEAD,
    "crm.summarize_deal": CRM_SUMMARIZE_DEAL,
    "crm.suggest_activity": CRM_SUGGEST_ACTIVITY,
    "crm.suggest_deal_probability": CRM_SUGGEST_DEAL_PROBABILITY,
    "moderation.content_review": MODERATION_CONTENT_REVIEW,
    "scheduled.weekly_sales_report": SCHEDULED_WEEKLY_SALES,
    "scheduled.overdue_invoices": SCHEDULED_OVERDUE_INVOICES,
    "scheduled.low_stock_alert": SCHEDULED_LOW_STOCK,
    "scheduled.monthly_summary": SCHEDULED_MONTHLY_SUMMARY,
    "insight.suggestion.daily_summary": INSIGHT_SUGGESTION_DAILY_SUMMARY,
    "insight.suggestion.invoice_guide": INSIGHT_SUGGESTION_INVOICE_GUIDE,
    "insight.suggestion.weekly_sales": INSIGHT_SUGGESTION_WEEKLY_SALES,
    "insight.suggestion.debtors": INSIGHT_SUGGESTION_DEBTORS,
    "insight.suggestion.low_stock": INSIGHT_SUGGESTION_LOW_STOCK,
    "insight.suggestion.sales_drop": INSIGHT_SUGGESTION_SALES_DROP,
    "insight.alert.low_stock_action": INSIGHT_ALERT_LOW_STOCK_ACTION,
    "insight.alert.debtors_action": INSIGHT_ALERT_DEBTORS_ACTION,
    "insight.alert.sales_drop_action": INSIGHT_ALERT_SALES_DROP_ACTION,
    "insight.alert.sales_growth_action": INSIGHT_ALERT_SALES_GROWTH_ACTION,
    "insight.alert.no_sales_today_action": INSIGHT_ALERT_NO_SALES_TODAY_ACTION,
    "insight.proactive.no_sales_today": INSIGHT_PROACTIVE_NO_SALES_TODAY,
    "insight.proactive.high_receivables": INSIGHT_PROACTIVE_HIGH_RECEIVABLES,
    "insight.proactive.critical_stock": INSIGHT_PROACTIVE_CRITICAL_STOCK,
    "insight.proactive.sales_surge": INSIGHT_PROACTIVE_SALES_SURGE,
    "memory.goal_progress_action": MEMORY_GOAL_PROGRESS_ACTION,
    "memory.suggestion.fill": MEMORY_SUGGESTION_FILL,
    "memory.suggestion.track_goal": MEMORY_SUGGESTION_TRACK_GOAL,
}

AI_DEFAULT_PROMPT_ROWS: list[dict[str, str]] = [
    {
        "prompt_key": "chat.user.base",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "پرامپت پایه چت کاربر",
        "content": CHAT_USER_BASE,
    },
    {
        "prompt_key": "chat.query_filter",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "بلوک جست‌وجوی پیشرفته",
        "content": ADVANCED_QUERY_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.visualization",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "بلوک نمودار و جدول",
        "content": VISUALIZATION_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.workflow",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "بلوک اتوماسیون Workflow",
        "content": AI_WORKFLOW_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.operator",
        "role": "operator",
        "prompt_type": "system",
        "category": "chat",
        "title": "پرامپت چت اپراتور",
        "content": CHAT_OPERATOR,
    },
    {
        "prompt_key": "chat.admin",
        "role": "admin",
        "prompt_type": "system",
        "category": "chat",
        "title": "پرامپت چت مدیر سیستم",
        "content": CHAT_ADMIN,
    },
    {
        "prompt_key": "aux.history_summary",
        "role": "user",
        "prompt_type": "system",
        "category": "auxiliary",
        "title": "خلاصه‌سازی تاریخچه مکالمه",
        "content": AUX_HISTORY_SUMMARY,
    },
    {
        "prompt_key": "aux.exploration",
        "role": "user",
        "prompt_type": "system",
        "category": "auxiliary",
        "title": "تحلیل نتایج ابزارها",
        "content": AUX_EXPLORATION,
    },
    {
        "prompt_key": "aux.chat_title",
        "role": "user",
        "prompt_type": "system",
        "category": "auxiliary",
        "title": "تولید عنوان گفت‌وگو",
        "content": AUX_CHAT_TITLE,
    },
    {
        "prompt_key": "aux.chat_title_user",
        "role": "user",
        "prompt_type": "user",
        "category": "auxiliary",
        "title": "پیام کاربر برای تولید عنوان",
        "content": AUX_CHAT_TITLE_USER,
    },
    {
        "prompt_key": "support.ticket_suggest.system",
        "role": "operator",
        "prompt_type": "system",
        "category": "support",
        "title": "پیشنهاد پاسخ تیکت — system",
        "content": SUPPORT_TICKET_SYSTEM,
    },
    {
        "prompt_key": "support.ticket_suggest.user",
        "role": "operator",
        "prompt_type": "user",
        "category": "support",
        "title": "پیشنهاد پاسخ تیکت — user",
        "content": SUPPORT_TICKET_USER,
    },
    {
        "prompt_key": "crm.summarize_lead",
        "role": "user",
        "prompt_type": "system",
        "category": "crm",
        "title": "خلاصه سرنخ CRM",
        "content": CRM_SUMMARIZE_LEAD,
    },
    {
        "prompt_key": "crm.summarize_deal",
        "role": "user",
        "prompt_type": "system",
        "category": "crm",
        "title": "خلاصه فرصت فروش CRM",
        "content": CRM_SUMMARIZE_DEAL,
    },
    {
        "prompt_key": "crm.suggest_activity",
        "role": "user",
        "prompt_type": "system",
        "category": "crm",
        "title": "پیشنهاد متن فعالیت CRM",
        "content": CRM_SUGGEST_ACTIVITY,
    },
    {
        "prompt_key": "crm.suggest_deal_probability",
        "role": "user",
        "prompt_type": "system",
        "category": "crm",
        "title": "پیشنهاد احتمال موفقیت فرصت",
        "content": CRM_SUGGEST_DEAL_PROBABILITY,
    },
    {
        "prompt_key": "moderation.content_review",
        "role": "admin",
        "prompt_type": "user",
        "category": "moderation",
        "title": "بررسی محتوای پیامک/ایمیل",
        "content": MODERATION_CONTENT_REVIEW,
    },
    {
        "prompt_key": "scheduled.weekly_sales_report",
        "role": "user",
        "prompt_type": "user",
        "category": "scheduled",
        "title": "گزارش فروش هفتگی",
        "content": SCHEDULED_WEEKLY_SALES,
    },
    {
        "prompt_key": "scheduled.overdue_invoices",
        "role": "user",
        "prompt_type": "user",
        "category": "scheduled",
        "title": "فاکتورهای معوق",
        "content": SCHEDULED_OVERDUE_INVOICES,
    },
    {
        "prompt_key": "scheduled.low_stock_alert",
        "role": "user",
        "prompt_type": "user",
        "category": "scheduled",
        "title": "هشدار موجودی کم",
        "content": SCHEDULED_LOW_STOCK,
    },
    {
        "prompt_key": "scheduled.monthly_summary",
        "role": "user",
        "prompt_type": "user",
        "category": "scheduled",
        "title": "خلاصه ماهانه",
        "content": SCHEDULED_MONTHLY_SUMMARY,
    },
    {
        "prompt_key": "insight.suggestion.daily_summary",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: خلاصه وضعیت امروز",
        "content": INSIGHT_SUGGESTION_DAILY_SUMMARY,
    },
    {
        "prompt_key": "insight.suggestion.invoice_guide",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: راهنمای ثبت فاکتور",
        "content": INSIGHT_SUGGESTION_INVOICE_GUIDE,
    },
    {
        "prompt_key": "insight.suggestion.weekly_sales",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: تحلیل فروش هفتگی",
        "content": INSIGHT_SUGGESTION_WEEKLY_SALES,
    },
    {
        "prompt_key": "insight.suggestion.debtors",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: پیگیری بدهکاران",
        "content": INSIGHT_SUGGESTION_DEBTORS,
    },
    {
        "prompt_key": "insight.suggestion.low_stock",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: هشدار موجودی",
        "content": INSIGHT_SUGGESTION_LOW_STOCK,
    },
    {
        "prompt_key": "insight.suggestion.sales_drop",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: علت افت فروش",
        "content": INSIGHT_SUGGESTION_SALES_DROP,
    },
    {
        "prompt_key": "insight.alert.low_stock_action",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "هشدار: اقدام کم‌موجودی",
        "content": INSIGHT_ALERT_LOW_STOCK_ACTION,
    },
    {
        "prompt_key": "insight.alert.debtors_action",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "هشدار: اقدام بدهکاران",
        "content": INSIGHT_ALERT_DEBTORS_ACTION,
    },
    {
        "prompt_key": "insight.alert.sales_drop_action",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "هشدار: اقدام افت فروش",
        "content": INSIGHT_ALERT_SALES_DROP_ACTION,
    },
    {
        "prompt_key": "insight.alert.sales_growth_action",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "هشدار: اقدام رشد فروش",
        "content": INSIGHT_ALERT_SALES_GROWTH_ACTION,
    },
    {
        "prompt_key": "insight.alert.no_sales_today_action",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "هشدار: اقدام بدون فروش امروز",
        "content": INSIGHT_ALERT_NO_SALES_TODAY_ACTION,
    },
    {
        "prompt_key": "insight.proactive.no_sales_today",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیش‌فعال: بدون فروش امروز",
        "content": INSIGHT_PROACTIVE_NO_SALES_TODAY,
    },
    {
        "prompt_key": "insight.proactive.high_receivables",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیش‌فعال: بدهی بالا",
        "content": INSIGHT_PROACTIVE_HIGH_RECEIVABLES,
    },
    {
        "prompt_key": "insight.proactive.critical_stock",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیش‌فعال: موجودی بحرانی",
        "content": INSIGHT_PROACTIVE_CRITICAL_STOCK,
    },
    {
        "prompt_key": "insight.proactive.sales_surge",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیش‌فعال: رشد فروش",
        "content": INSIGHT_PROACTIVE_SALES_SURGE,
    },
    {
        "prompt_key": "memory.goal_progress_action",
        "role": "user",
        "prompt_type": "user",
        "category": "memory",
        "title": "حافظه: اقدام پیشرفت هدف",
        "content": MEMORY_GOAL_PROGRESS_ACTION,
    },
    {
        "prompt_key": "memory.suggestion.fill",
        "role": "user",
        "prompt_type": "user",
        "category": "memory",
        "title": "حافظه: پیشنهاد تکمیل حافظه",
        "content": MEMORY_SUGGESTION_FILL,
    },
    {
        "prompt_key": "memory.suggestion.track_goal",
        "role": "user",
        "prompt_type": "user",
        "category": "memory",
        "title": "حافظه: پیگیری هدف فروش",
        "content": MEMORY_SUGGESTION_TRACK_GOAL,
    },
]

SCHEDULED_TASK_PROMPT_KEYS: dict[str, str] = {
    "weekly_sales_report": "scheduled.weekly_sales_report",
    "overdue_invoices": "scheduled.overdue_invoices",
    "low_stock_alert": "scheduled.low_stock_alert",
    "monthly_summary": "scheduled.monthly_summary",
}
