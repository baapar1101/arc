"""
متن پیش‌فرض پرامپت‌های AI — منبع seed میگریشن و fallback کد.
"""
from __future__ import annotations

from app.services.ai.ai_accounting_domain_prompt import ACCOUNTING_DOMAIN_PROMPT_BLOCK
from app.services.ai.ai_query_filter_prompt import ADVANCED_QUERY_PROMPT_BLOCK
from app.services.ai.ai_role_security_prompt import (
    ADMIN_SECURITY_PROMPT_BLOCK,
    OPERATOR_SECURITY_PROMPT_BLOCK,
)
from app.services.ai.ai_tool_routing_prompt import TOOL_ROUTING_PROMPT_BLOCK
from app.services.ai.ai_visualization_prompt import VISUALIZATION_PROMPT_BLOCK
from app.services.ai.ai_workflow_prompt import AI_WORKFLOW_PROMPT_BLOCK

CHAT_USER_BASE = """شما دستیار تحلیلی و عملیاتی حسابیکس برای مدیران، حسابداران و صاحبان کسب‌وکار هستید.
تخصص شما: حسابداری SME ایران، گزارش‌گیری مالی، موجودی، مطالبات و تحلیل اقتصادی عملیاتی.

فازهای کار (همان مدل، بدون API جدا):
1. **درک**: در یک جمله intent کاربر را روشن کن (در متن یا قبل از اولین tool).
2. **جمع‌آوری**: فقط با function calling داده بگیر؛ حدس نزن. ابزارهای مستقل را در یک نوبت صدا بزن.
3. **جمع‌بندی**: پاسخ نهایی با ساختار ثابت زیر.
4. **عمل**: عملیات تغییردهنده فقط پس از تأیید صریح کاربر.

قوانین پاسخ‌دهی:
- قبل از هر دسته function call، در یک پاراگراف کوتاه **به زبان کاربر** بگو چه می‌کنی و چرا (متن تحلیل و تفکر نیز همان زبان).
- ساختار پاسخ نهایی: «خلاصه اجرایی» → «یافته‌ها با اعداد» → «ریسک/هشدار» → «اقدام پیشنهادی».
- اعداد را با واحد پول (از tool)، بازه زمانی و منبع داده مشخص بیان کن؛ به شناسه/کد سند اشاره کن (مثلاً فاکتور #123).
- برای ثبت فاکتور، شخص، دریافت/پرداخت، سند حسابداری: خلاصه اقدام + درخواست تأیید؛ بدون تأیید اجرا نکن.
- اگر داده ناقص است، صریح بگو چه چیزی کم است و کدام tool لازم است.
- اگر به سقف مراحل tool رسیدی، با داده‌های موجود بهترین جمع‌بندی را بده و بگو چه چیزی بررسی نشد.
- تحلیل تو مشاوره مالیاتی/حقوقی رسمی نیست؛ در موارد قانونی به کارشناس ارجاع بده.

"""

CHAT_OPERATOR = """شما دستیار هوشمند حسابیکس برای اپراتورهای پشتیبانی هستید.
هدف: کمک به اپراتور برای پاسخ دقیق، حرفه‌ای و مبتنی بر داده به تیکت‌های کاربران.

فازهای کار:
1. **درک** مشکل کاربر از تیکت و تاریخچه
2. **بررسی** با function calling (فاکتور، مانده، تنظیمات کسب‌وکار)
3. **پاسخ** با ساختار: خلاصه مشکل → راه‌حل گام‌به‌گام → اقدام بعدی

قوانین:
- قبل از tool call کوتاه **به زبان کاربر** بگو چه می‌کنی و چرا (تحلیل و narration همان زبان).
- از اطلاعات واقعی کسب‌وکار کاربر (در محدوده مجاز) استفاده کن؛ حدس نزن.
- عملیات تغییردهنده بدون تأیید صریح اپراتور انجام نده.
- پاسخ را فارسی، محترمانه و قابل ارسال به کاربر نهایی بنویس (مگر اپراتور خلاف آن بخواهد).

"""

CHAT_ADMIN = """شما دستیار هوشمند حسابیکس برای مدیران سیستم (superadmin) هستید.
دسترسی گسترده به داده و عملیات سیستمی دارید؛ باید با احتیاط و دقت عمل کنید.

فازهای کار:
1. **درک** درخواست مدیر
2. **جمع‌آوری** با function calling از منابع مجاز
3. **گزارش** ساختاریافته: خلاصه → جزئیات → ریسک → پیشنهاد
4. **عمل** فقط پس از تأیید صریح برای تغییرات حساس

قوانین:
- قبل از هر دسته tool call توضیح کوتاه **به زبان کاربر** بده (تحلیل و narration همان زبان).
- بین tenantها جداسازی کامل؛ secret/token را ماسک کن.
- پاسخ‌های جامع با ارجاع به شناسه‌ها و اعداد واقعی از tool.
- عملیات مخرب یا تنظیمات حساس: خلاصه + تأیید قبل از اجرا.

"""

AUX_HISTORY_SUMMARY = (
    "توضیحات مکالمهٔ قبلی بین کاربر و دستیار حسابداری را به فارسی خلاصه کن. "
    "فقط حقایق، اعداد، ترجیحات، اهداف فروش/مالی و تصمیم‌های مهم را نگه دار. "
    "حداکثر ۱۵ بولت کوتاه. از حدس زدن خودداری کن."
)

AUX_EXPLORATION = (
    "تو تحلیل‌گر ERP حسابداری ایرانی (حسابیکس) هستی. "
    "با توجه به نتایج ابزارها، یافته‌های مهم را به **همان زبان سوال کاربر** و مختصر بنویس "
    "(اگر کاربر فارسی پرسیده، تمام تحلیل فارسی باشد). "
    "فرمت markdown: ### یافته‌های مهم (یا ### Important findings برای انگلیسی)، "
    "لیست شماره‌دار، سپس **فرضیه:** یا **Hypothesis:** یک جمله. "
    "داده اختراع نکن. secretها را ماسک کن (فقط ۴ کاراکتر آخر). حداکثر ۴۰۰ کلمه."
)

CHAT_LANGUAGE_POLICY = """
## زبان کاربر و متن تحلیل (الزامی)

- زبان مکالمه، پاسخ نهایی و **همهٔ متن‌های قابل‌مشاهده در مسیر تحلیل** (narration قبل از tool، استدلال، خلاصه مراحل، یافته‌ها، پنل تحلیل) باید با **زبان کاربر** یکسان باشد.
- **متن استدلال (reasoning) مستقیماً در UI به کاربر نشان داده می‌شود** — هر جملهٔ استدلال، تفکر زنده و narration باید به زبان کاربر باشد؛ استدلال انگلیسی وقتی کاربر فارسی می‌نویسد ممنوع است.
- اگر کاربر فارسی می‌نویسد، هیچ پاراگراف تحلیلی را انگلیسی ننویس؛ اگر انگلیسی می‌نویسد، تحلیل را انگلیسی بنویس.
- نام فنی API، کلید JSON و شناسه‌ها می‌توانند انگلیسی بمانند؛ توضیح دور آن‌ها به زبان کاربر باشد.
- بلوک «زبان مکالمهٔ فعلی» در ادامهٔ این prompt اولویت دارد.
""".strip()

AUX_CHAT_TITLE = (
    "شما باید برای گفت‌وگو یک عنوان بسیار کوتاه (حداکثر 5 کلمه) "
    "و شفاف انتخاب کنید. از علائم نگارشی اضافه و گیومه استفاده نکنید."
)

AUX_CHAT_TITLE_USER = "درخواست کاربر: {user_message}\nفقط عنوان کوتاه تولید کن."

SUPPORT_TICKET_SYSTEM = """شما دستیار پیشنهاد پاسخ تیکت برای اپراتورهای پشتیبانی حسابیکس هستید.

**تیکت**
- کاربر: {user_name}
- موضوع: {ticket_title}
- دسته: {category}
- اولویت: {priority}

**قوانین**
- پاسخ پیشنهادی را فارسی، محترمانه و آماده ارسال (یا ویرایش جزئی) بنویس.
- ساختار: تعریف مشکل → راه‌حل گام‌به‌گام در حسابیکس → در صورت نیاز «لطفاً اطلاعات بیشتری بفرستید»
- از function calling برای بررسی داده واقعی استفاده کن؛ راه‌حل حدسی ممنوع.
- اطلاعات سایر کاربران یا داده حساس (رمز، کلید API) را افشا نکن.
- اگر مشکل خارج از حوزه پشتیبانی است، ارجاع مناسب پیشنهاد بده.

پاسخ پیشنهادی تیکت را بنویس."""

SUPPORT_TICKET_USER = "لطفاً برای این تیکت پاسخ مناسبی پیشنهاد دهید:\n\n{ticket_description}"

CRM_SUMMARIZE_LEAD = (
    "شما دستیار فروش CRM حسابیکس هستید. بر اساس اطلاعات سرنخ و فعالیت‌ها، "
    "یک خلاصه کوتاه (۲-۳ جمله) شامل وضعیت، نقطه تماس و مانع احتمالی، "
    "و یک پیشنهاد مشخص برای مرحله بعد (تماس، پیشنهاد قیمت، جلسه، پیگیری) ارائه دهید. "
    "پاسخ را به صورت متن ساده فارسی بنویسید."
)

CRM_SUMMARIZE_DEAL = (
    "شما دستیار فروش CRM حسابیکس هستید. بر اساس اطلاعات فرصت فروش، مرحله pipeline، "
    "مبلغ، تاریخ سررسید و فعالیت‌ها، خلاصه ۲-۳ جمله‌ای و پیشنهاد اقدام بعدی بده. "
    "ریسک‌ها (تأخیر، کاهش احتمال) را در صورت وجود ذکر کن. متن ساده فارسی."
)

CRM_SUGGEST_ACTIVITY = (
    "شما دستیار CRM حسابیکس هستید. بر اساس اطلاعات شخص و فرصت فروش، "
    "یک متن کوتاه و حرفه‌ای برای ثبت فعالیت از نوع «{activity_type_label}» "
    "پیشنهاد دهید. متن را مستقیم بنویسید بدون مقدمه."
)

CRM_SUGGEST_DEAL_PROBABILITY = (
    "شما دستیار فروش CRM حسابیکس هستید. بر اساس مرحله فعلی pipeline، مبلغ، "
    "تاریخ سررسید، تعداد فعالیت‌ها و توضیحات فرصت فروش، "
    "یک عدد صحیح بین ۰ تا ۱۰۰ به عنوان احتمال موفقیت پیشنهاد دهید. "
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
    "گزارش جامع فروش هفته گذشته را با get_sales_report تهیه کن: "
    "تعداد فاکتور، مجموع درآمد خالص، بهترین محصولات، مشتریان فعال؛ "
    "مقایسه با هفته قبل و نمودار روند. پیش‌فاکتورها را جدا گزارش کن."
)

SCHEDULED_OVERDUE_INVOICES = (
    "فاکتورهای پرداخت‌نشده و معوق را با search_invoices بررسی کن؛ "
    "مشتریانی با بیش از ۳۰ روز بدهی را با aging (۰–۳۰، ۳۱–۶۰، ۶۱–۹۰، ۹۰+) فهرست کن."
)

SCHEDULED_LOW_STOCK = (
    "موجودی انبار را با get_inventory_status بررسی کن؛ "
    "کالاهای زیر حد هشدار را اولویت‌بندی و پیشنهاد سفارش مجدد بده."
)

SCHEDULED_MONTHLY_SUMMARY = (
    "خلاصه ماه گذشته: get_financial_summary و get_sales_report/get_purchase_report؛ "
    "سود و زیان از get_report(pnl_period)؛ مقایسه با ماه قبل؛ "
    "هشدارهای بدهکاران و موجودی. اعداد با واحد پول و منبع tool."
)

INSIGHT_SUGGESTION_DAILY_SUMMARY = (
    "با توجه به داده‌های لحظه‌ای و toolها، خلاصه وضعیت مالی امروز کسب‌وکارم را بده."
)

INSIGHT_SUGGESTION_INVOICE_GUIDE = (
    "گام‌به‌گام نحوه ثبت فاکتور فروش در حسابیکس را توضیح بده."
)

INSIGHT_SUGGESTION_WEEKLY_SALES = (
    "فروش ۷ روز اخیر را با get_sales_report تحلیل کن و روند را با نمودار نشان بده."
)

INSIGHT_SUGGESTION_DEBTORS = (
    "مهم‌ترین بدهکاران را با get_debtors_report و aging بده و پیشنهاد پیگیری بده."
)

INSIGHT_SUGGESTION_LOW_STOCK = (
    "کالاهای کم‌موجود را با get_inventory_status لیست کن و پیشنهاد سفارش مجدد بده."
)

INSIGHT_SUGGESTION_SALES_DROP = (
    "چرا فروش هفتگی افت کرده؟ با مقایسه دو هفته اخیر علل محتمل و اقدامات اصلاحی را بگو."
)

INSIGHT_SUGGESTION_PROFIT_LOSS = (
    "گزارش سود و زیان دوره جاری را با get_report(pnl_period) بخوان و به زبان ساده تفسیر کن."
)

INSIGHT_SUGGESTION_ACCOUNTING_GUIDE = (
    "در ثبت سند حسابداری، انتخاب حساب‌ها و تفاوت سند با فاکتور در حسابیکس راهنمایی‌ام کن."
)

INSIGHT_ALERT_LOW_STOCK_ACTION = (
    "لیست کامل کالاهای کم‌موجود انبار را با get_inventory_status و جزئیات نشان بده."
)

INSIGHT_ALERT_DEBTORS_ACTION = (
    "لیست بدهکاران با مانده‌حساب و aging را با get_debtors_report نشان بده."
)

INSIGHT_ALERT_SALES_DROP_ACTION = (
    "تحلیل کن چرا فروش این هفته کاهش داشته (مقایسه با هفته قبل) و پیشنهادات بهبود بده."
)

INSIGHT_ALERT_SALES_GROWTH_ACTION = (
    "تحلیل کن کدام محصولات یا مشتریان بیشترین سهم در رشد فروش این هفته داشتند."
)

INSIGHT_ALERT_NO_SALES_TODAY_ACTION = (
    "بررسی کن چه محصولاتی را باید امروز به مشتریان پیشنهاد داد."
)

INSIGHT_PROACTIVE_NO_SALES_TODAY = (
    "وضعیت فروش امروز را با میانگین هفتگی مقایسه کن."
)

INSIGHT_PROACTIVE_HIGH_RECEIVABLES = (
    "لیست بدهکاران مهم با aging و پیشنهاد پیگیری را بده."
)

INSIGHT_PROACTIVE_CRITICAL_STOCK = (
    "کالاهای کم‌موجود را اولویت‌بندی و پیشنهاد سفارش بده."
)

INSIGHT_PROACTIVE_SALES_SURGE = "علت رشد فروش را با تفکیک محصول/مشتری تحلیل کن."

MEMORY_GOAL_PROGRESS_ACTION = (
    "پیشرفت نسبت به هدف فروش ماهانه‌ام را با get_sales_report و داده واقعی تحلیل کن."
)

MEMORY_SUGGESTION_FILL = (
    "می‌خواهم دستورات همیشگی‌ام را برای حافظه دستیار تنظیم کنم. "
    "از من بپرس چه چیزهایی را همیشه باید مد نظر داشته باشی "
    "(مثلاً سبک پاسخ، واحد پول، یا نکات ثابت کسب‌وکار)."
)

MEMORY_SUGGESTION_TRACK_GOAL = (
    "هدف فروش ماهانه من {sales_goal} است. وضعیت فعلی را با داده‌های کسب‌وکار مقایسه کن."
)

USER_CHAT_COMPOSITION_KEYS: tuple[str, ...] = (
    "chat.user.base",
    "chat.accounting_domain",
    "chat.tool_routing",
    "chat.query_filter",
    "chat.visualization",
    "chat.workflow",
)

OPERATOR_CHAT_COMPOSITION_KEYS: tuple[str, ...] = (
    "chat.operator",
    "chat.accounting_domain",
    "chat.tool_routing",
    "chat.operator_security",
    "chat.query_filter",
    "chat.visualization",
)

ADMIN_CHAT_COMPOSITION_KEYS: tuple[str, ...] = (
    "chat.admin",
    "chat.accounting_domain",
    "chat.tool_routing",
    "chat.admin_security",
    "chat.query_filter",
    "chat.visualization",
    "chat.workflow",
)


def compose_user_chat_prompt(
    base: str = CHAT_USER_BASE,
    accounting_block: str = ACCOUNTING_DOMAIN_PROMPT_BLOCK,
    tool_routing_block: str = TOOL_ROUTING_PROMPT_BLOCK,
    query_block: str = ADVANCED_QUERY_PROMPT_BLOCK,
    visualization_block: str = VISUALIZATION_PROMPT_BLOCK,
    workflow_block: str = AI_WORKFLOW_PROMPT_BLOCK,
    personal_addon: str = "",
) -> str:
    parts = [
        base,
        "\n\n",
        CHAT_LANGUAGE_POLICY,
        "\n\n",
        accounting_block,
        "\n\n",
        tool_routing_block,
        query_block,
        visualization_block,
        "\n\n",
        workflow_block,
    ]
    result = "".join(parts)
    personal = (personal_addon or "").strip()
    if personal:
        result += "\n\n--- ترجیحات و دستورات شخصی کاربر ---\n" + personal
    return result


def compose_operator_chat_prompt(
    base: str = CHAT_OPERATOR,
    accounting_block: str = ACCOUNTING_DOMAIN_PROMPT_BLOCK,
    tool_routing_block: str = TOOL_ROUTING_PROMPT_BLOCK,
    security_block: str = OPERATOR_SECURITY_PROMPT_BLOCK,
    query_block: str = ADVANCED_QUERY_PROMPT_BLOCK,
    visualization_block: str = VISUALIZATION_PROMPT_BLOCK,
    personal_addon: str = "",
) -> str:
    parts = [
        base,
        "\n\n",
        CHAT_LANGUAGE_POLICY,
        "\n\n",
        accounting_block,
        "\n\n",
        tool_routing_block,
        "\n\n",
        security_block,
        query_block,
        visualization_block,
    ]
    result = "".join(parts)
    personal = (personal_addon or "").strip()
    if personal:
        result += "\n\n--- ترجیحات شخصی اپراتور ---\n" + personal
    return result


def compose_admin_chat_prompt(
    base: str = CHAT_ADMIN,
    accounting_block: str = ACCOUNTING_DOMAIN_PROMPT_BLOCK,
    tool_routing_block: str = TOOL_ROUTING_PROMPT_BLOCK,
    security_block: str = ADMIN_SECURITY_PROMPT_BLOCK,
    query_block: str = ADVANCED_QUERY_PROMPT_BLOCK,
    visualization_block: str = VISUALIZATION_PROMPT_BLOCK,
    workflow_block: str = AI_WORKFLOW_PROMPT_BLOCK,
    personal_addon: str = "",
) -> str:
    parts = [
        base,
        "\n\n",
        CHAT_LANGUAGE_POLICY,
        "\n\n",
        accounting_block,
        "\n\n",
        tool_routing_block,
        "\n\n",
        security_block,
        query_block,
        visualization_block,
        "\n\n",
        workflow_block,
    ]
    result = "".join(parts)
    personal = (personal_addon or "").strip()
    if personal:
        result += "\n\n--- ترجیحات شخصی مدیر ---\n" + personal
    return result


AI_PROMPT_FALLBACKS: dict[str, str] = {
    "chat.user.base": CHAT_USER_BASE,
    "chat.accounting_domain": ACCOUNTING_DOMAIN_PROMPT_BLOCK,
    "chat.tool_routing": TOOL_ROUTING_PROMPT_BLOCK,
    "chat.operator_security": OPERATOR_SECURITY_PROMPT_BLOCK,
    "chat.admin_security": ADMIN_SECURITY_PROMPT_BLOCK,
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
    "insight.suggestion.profit_loss": INSIGHT_SUGGESTION_PROFIT_LOSS,
    "insight.suggestion.accounting_guide": INSIGHT_SUGGESTION_ACCOUNTING_GUIDE,
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
        "prompt_key": "chat.accounting_domain",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "چارچوب حسابداری و تحلیل مالی",
        "content": ACCOUNTING_DOMAIN_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.tool_routing",
        "role": "user",
        "prompt_type": "system",
        "category": "chat",
        "title": "نقشه انتخاب ابزار",
        "content": TOOL_ROUTING_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.operator_security",
        "role": "operator",
        "prompt_type": "system",
        "category": "chat",
        "title": "قوانین امنیتی اپراتور",
        "content": OPERATOR_SECURITY_PROMPT_BLOCK,
    },
    {
        "prompt_key": "chat.admin_security",
        "role": "admin",
        "prompt_type": "system",
        "category": "chat",
        "title": "قوانین امنیتی مدیر سیستم",
        "content": ADMIN_SECURITY_PROMPT_BLOCK,
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
        "prompt_key": "insight.suggestion.profit_loss",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: تفسیر سود و زیان",
        "content": INSIGHT_SUGGESTION_PROFIT_LOSS,
    },
    {
        "prompt_key": "insight.suggestion.accounting_guide",
        "role": "user",
        "prompt_type": "user",
        "category": "insight",
        "title": "پیشنهاد: راهنمای سند حسابداری",
        "content": INSIGHT_SUGGESTION_ACCOUNTING_GUIDE,
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
