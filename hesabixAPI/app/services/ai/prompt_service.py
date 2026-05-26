from __future__ import annotations

from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from adapters.db.models.ai_prompt import AIPrompt, PromptRole, PromptType
from adapters.db.repositories.ai_prompt_repository import AIPromptRepository


def get_prompt(
    db: Session,
    role: PromptRole,
    user_id: Optional[int] = None,
    prompt_type: PromptType = PromptType.SYSTEM
) -> str:
    """
    دریافت prompt با اولویت:
    1. Prompt شخصی کاربر (اگر user_id داده شده)
    2. Prompt پیش‌فرض سیستم
    3. Prompt سخت‌کد شده
    """
    repo = AIPromptRepository(db)
    
    # اول: جستجوی prompt شخصی کاربر
    if user_id:
        user_prompt = repo.get_user_prompt(user_id, role, prompt_type)
        if user_prompt:
            return user_prompt.content
    
    # دوم: جستجوی prompt پیش‌فرض
    default_prompt = repo.get_default_prompt(role, prompt_type)
    if default_prompt:
        return default_prompt.content
    
    # سوم: prompt پیش‌فرض سخت‌کد شده
    return _get_default_prompt(role)


def _get_default_prompt(role: PromptRole) -> str:
    """Prompt های پیش‌فرض سخت‌کد شده"""
    defaults = {
        PromptRole.OPERATOR: """شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
وظیفه شما کمک به اپراتورها در پاسخ به تیکت‌های کاربران است.
باید پاسخ‌های حرفه‌ای، مفید و دقیق ارائه دهید.
از اطلاعات کسب‌وکار کاربر برای ارائه پاسخ بهتر استفاده کنید.""",
        
        PromptRole.USER: """شما دستیار تحلیلی و عملیاتی حسابیکس برای مدیران و حسابداران هستید.

قوانین پاسخ‌دهی:
1. قبل از نتیجه‌گیری، با function calling داده بگیر؛ حدس نزن.
2. قبل از هر دسته function call، در یک پاراگراف کوتاه به فارسی توضیح بده چه می‌خواهی انجام دهی و چرا (مثلاً «ابتدا گزارش فروش سه ماه اخیر را می‌گیرم تا روند را ببینم»).
3. ساختار پاسخ نهایی: «خلاصه اجرایی» → «یافته‌ها با اعداد» → «ریسک/هشدار» → «اقدام پیشنهادی».
4. اعداد را با واحد پول و بازه زمانی مشخص بیان کن.
5. برای عملیات تغییردهنده (ثبت فاکتور، شخص، دریافت/پرداخت) ابتدا خلاصه اقدام را بگو و تأیید بخواه؛ بدون تأیید کاربر اجرا نکن.
6. اگر داده ناقص است، صریح بگو چه اطلاعاتی کم است.

از ابزارهای موجود برای گزارش فروش، موجودی، بدهکاران، جریان نقدی و CRM استفاده کن.

برای نمایش روند عددی از بلوک نمودار استفاده کن (فقط JSON معتبر):
```chart
{"type":"bar","title":"عنوان","labels":["برچسب۱"],"values":[100],"unit":"اختیاری"}
```""",
        
        PromptRole.ADMIN: """شما یک دستیار هوشمند برای مدیران سیستم هستید.
می‌توانید به تمام بخش‌های سیستم دسترسی داشته باشید.
باید پاسخ‌های دقیق و جامع ارائه دهید.
از function calling برای دسترسی به داده‌های سیستم استفاده کنید."""
    }
    return defaults.get(role, "")


def create_user_prompt(
    db: Session,
    user_id: int,
    role: PromptRole,
    title: str,
    content: str,
    prompt_type: PromptType = PromptType.SYSTEM
) -> AIPrompt:
    """ایجاد prompt شخصی برای کاربر"""
    prompt = AIPrompt(
        role=role.value,
        prompt_type=prompt_type.value,
        title=title,
        content=content,
        user_id=user_id,
        is_default=False,
        is_active=True
    )
    db.add(prompt)
    db.commit()
    db.refresh(prompt)
    return prompt


def update_default_prompt(
    db: Session,
    role: PromptRole,
    content: str,
    prompt_type: PromptType = PromptType.SYSTEM
) -> AIPrompt:
    """به‌روزرسانی prompt پیش‌فرض (فقط برای مدیر سیستم)"""
    repo = AIPromptRepository(db)
    prompt = repo.get_default_prompt(role, prompt_type)
    
    if prompt:
        prompt.content = content
    else:
        prompt = AIPrompt(
            role=role.value,
            prompt_type=prompt_type.value,
            title=f"Prompt پیش‌فرض {role.value}",
            content=content,
            user_id=None,
            is_default=True,
            is_active=True
        )
        db.add(prompt)
    
    db.commit()
    db.refresh(prompt)
    return prompt

