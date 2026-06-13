"""
سرویس بررسی خودکار محتوای قالب‌های نوتیفیکیشن با AI

این سرویس از LLM رایگان استفاده می‌کند و نیازی به اعتبار کسب‌وکار ندارد
"""
from __future__ import annotations

import re
import logging
import json
from typing import Any, Dict, List, Optional
from decimal import Decimal
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)


# کلمات کلیدی تبلیغاتی/spam
SPAM_KEYWORDS_FA = [
    "تخفیف ویژه", "فقط امروز", "رایگان", "جایزه", "کلیک کنید",
    "همین حالا", "محدود", "فوری", "شگفت‌انگیز", "باورنکردنی",
    "هدیه", "مسابقه", "قرعه‌کشی", "برنده شوید", "فرصت طلایی"
]

# Pattern های مشکوک
SUSPICIOUS_PATTERNS = [
    r"\d+%\s*تخفیف",  # 50% تخفیف
    r"فقط\s+\d+\s+روز",  # فقط 3 روز
    r"(کلیک|لینک|ورود).*همین\s+(الان|حالا)",  # کلیک کنید همین الان
    r"\d+\s*(میلیون|هزار)\s*(رایگان|هدیه)",  # 5 میلیون رایگان
    r"(خرید|ثبت\s*نام).*رایگان",  # خرید رایگان
]

# کلمات نامناسب (مثال‌های محدود)
PROFANITY_WORDS = [
    # این لیست باید کامل‌تر شود
]


@dataclass
class ModerationResult:
    """نتیجه بررسی محتوا"""
    decision: str  # approve, reject, review_required
    confidence: Decimal  # 0-100
    flags: List[str]  # لیست مشکلات یافت شده
    suggestions: Optional[str]  # پیشنهادات بهبود
    details: Dict[str, Any]  # جزئیات بیشتر


class SpamDetector:
    """تشخیص محتوای تبلیغاتی/spam"""
    
    def analyze(self, text: str) -> Dict[str, Any]:
        """
        تحلیل محتوا برای تشخیص spam
        
        Returns:
            دیکشنری با score و flags
        """
        score = 0
        flags = []
        
        # بررسی کلمات کلیدی
        for keyword in SPAM_KEYWORDS_FA:
            if keyword in text:
                score += 15
                flags.append(f"کلمه تبلیغاتی: '{keyword}'")
        
        # بررسی pattern ها
        for pattern in SUSPICIOUS_PATTERNS:
            matches = re.findall(pattern, text, re.IGNORECASE)
            if matches:
                score += 20
                flags.append(f"الگوی مشکوک یافت شد: {matches[0]}")
        
        # بررسی نسبت لینک به متن
        links = re.findall(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', text)
        if links:
            link_count = len(links)
            word_count = len(text.split())
            if word_count > 0:
                link_ratio = link_count / word_count
                if link_ratio > 0.1:  # بیش از 10% متن لینک است
                    score += 25
                    flags.append(f"تعداد زیاد لینک: {link_count}")
        
        # بررسی تکرار زیاد کاراکترهای خاص
        if text.count('!') > 3:
            score += 10
            flags.append("استفاده بیش از حد از علامت تعجب")
        
        # متن کوتاه اما پر از emoji/کاراکتر خاص
        emoji_pattern = r'[\U0001F300-\U0001F9FF]+'
        emoji_count = len(re.findall(emoji_pattern, text))
        if emoji_count > 5:
            score += 15
            flags.append(f"استفاده زیاد از emoji: {emoji_count}")
        
        return {
            "score": min(score, 100),
            "is_spam": score > 50,
            "flags": flags
        }


class ProfanityDetector:
    """تشخیص محتوای نامناسب"""
    
    def check(self, text: str) -> Dict[str, Any]:
        """بررسی محتوای نامناسب"""
        score = 0
        flags = []
        
        for word in PROFANITY_WORDS:
            if word in text.lower():
                score += 50
                flags.append(f"کلمه نامناسب یافت شد")
        
        return {
            "score": min(score, 100),
            "has_profanity": score > 0,
            "flags": flags
        }




class AIContentModerationService:
    """
    سرویس بررسی خودکار محتوای قالب‌های نوتیفیکیشن
    
    استفاده از AIService موجود در سیستم (یکپارچه با کیف پول و مدیریت اعتبار)
    
    ترکیبی از:
    1. Rule-based checks (سریع و دقیق)
    2. AI-based checks (از طریق AIService)
    
    توجه: این سرویس از اعتبار سیستم استفاده می‌کند، نه کاربر
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.spam_detector = SpamDetector()
        self.profanity_detector = ProfanityDetector()
    
    async def review_template(
        self,
        content: str,
        subject: Optional[str],
        event_type: str
    ) -> ModerationResult:
        """
        بررسی کامل یک قالب
        
        Args:
            content: محتوای قالب (body)
            subject: موضوع (برای email)
            event_type: نوع رویداد
        
        Returns:
            ModerationResult
        """
        flags = []
        details = {}
        
        # 1. بررسی‌های پایه
        base_checks = self._basic_checks(content)
        details["basic_checks"] = base_checks
        if not base_checks["passed"]:
            flags.extend(base_checks["issues"])
        
        # 2. تشخیص Spam
        spam_result = self.spam_detector.analyze(content)
        details["spam_check"] = spam_result
        if spam_result["is_spam"]:
            flags.extend(spam_result["flags"])
        
        # 3. بررسی محتوای نامناسب
        profanity_result = self.profanity_detector.check(content)
        details["profanity_check"] = profanity_result
        if profanity_result["has_profanity"]:
            flags.extend(profanity_result["flags"])
        
        # 4. بررسی با AI (از طریق AIService سیستم)
        ai_result = None
        try:
            ai_result = await self._ai_review(content, subject, event_type)
            details["ai_review"] = ai_result
            if ai_result and ai_result.get("is_promotional"):
                flags.append("AI: محتوا تبلیغاتی است")
            if ai_result and ai_result.get("is_spam"):
                flags.append("AI: محتوا spam است")
        except Exception as e:
            logger.warning(f"خطا در بررسی AI (ادامه با rule-based): {e}")
        
        # 5. تصمیم‌گیری نهایی
        decision, confidence = self._make_decision(
            spam_result, profanity_result, ai_result
        )
        
        # 6. پیشنهادات بهبود
        suggestions = self._generate_suggestions(flags, ai_result)
        
        return ModerationResult(
            decision=decision,
            confidence=confidence,
            flags=flags,
            suggestions=suggestions,
            details=details
        )
    
    def _basic_checks(self, content: str) -> Dict[str, Any]:
        """بررسی‌های اولیه"""
        issues = []
        
        # طول مناسب
        if len(content) < 10:
            issues.append("محتوا خیلی کوتاه است")
        
        if len(content) > 1000:
            issues.append("محتوا خیلی طولانی است (بیش از 1000 کاراکتر)")
        
        # بررسی متغیرها به درستی استفاده شده‌اند
        # ({{ variable_name }})
        invalid_vars = re.findall(r'\{[^{].*?\}', content)
        if invalid_vars:
            issues.append(f"استفاده نادرست از متغیر: باید از {{{{ variable }}}} استفاده کنید")
        
        return {
            "passed": len(issues) == 0,
            "issues": issues
        }
    
    async def _ai_review(
        self,
        content: str,
        subject: Optional[str],
        event_type: str
    ) -> Optional[Dict[str, Any]]:
        """
        بررسی محتوا با استفاده از AIService موجود
        
        این بررسی از اعتبار سیستم استفاده می‌کند (رایگان برای moderation)
        """
        try:
            from app.services.ai.ai_service import AIService
            from app.core.auth_dependency import AuthContext
            
            # ایجاد یک context سیستمی برای استفاده از AI
            # اپراتورها و سوپرادمین‌ها از AI بدون محدودیت استفاده می‌کنند
            system_ctx = self._create_system_context()
            
            # ایجاد AI Service
            ai_service = AIService(self.db, system_ctx, business_id=None)
            
            user_prompt = get_prompt_by_key(
                self.db,
                "moderation.content_review",
                {
                    "event_type": event_type,
                    "subject": subject or "ندارد",
                    "content": content,
                },
            )
            
            messages = [
                {"role": "user", "content": user_prompt}
            ]
            
            # ارسال به AI (بدون function calling)
            response = await ai_service.chat_completion(
                messages=messages,
                use_function_calling=False,
                max_tokens_override=500
            )
            
            # استخراج پاسخ
            ai_response = response["message"]["content"]
            
            # پارس JSON از پاسخ
            json_match = re.search(r'\{.*\}', ai_response, re.DOTALL)
            if json_match:
                json_text = json_match.group(0)
                result = json.loads(json_text)
                
                # ثبت استفاده (بدون شارژ - سیستمی)
                usage = response.get("usage", {})
                ai_service.log_usage(
                    provider=ai_service.config.provider if ai_service.config else "openai",
                    model=ai_service.config.model_name if ai_service.config else "gpt-4",
                    input_tokens=usage.get("input_tokens", 0),
                    output_tokens=usage.get("output_tokens", 0),
                    cost=0,  # رایگان برای سیستم
                    payment_method="system",
                    wallet_transaction_id=None,
                    document_id=None,
                    context={"type": "content_moderation", "event_type": event_type}
                )
                
                return result
            else:
                logger.warning("Could not extract JSON from AI response")
                return None
                
        except ApiError as e:
            # اگر AI در دسترس نیست یا مشکلی دارد، برمی‌گردیم None
            logger.warning(f"AI service not available for moderation: {e.message}")
            return None
        except Exception as e:
            logger.error(f"Error in AI review: {e}", exc_info=True)
            return None
    
    def _create_system_context(self) -> AuthContext:
        """
        ایجاد یک AuthContext سیستمی برای استفاده از AIService
        
        این context به عنوان superadmin شناخته می‌شود و بدون محدودیت
        از AI استفاده می‌کند
        """
        from adapters.db.models.user import User
        from app.core.responses import ApiError
        
        # پیدا کردن یک کاربر superadmin سیستم
        system_user = self.db.query(User).filter(
            User.is_superadmin == True,
            User.is_active == True
        ).first()
        
        if not system_user:
            raise ApiError(
                "SYSTEM_USER_NOT_FOUND",
                "کاربر سیستمی برای AI یافت نشد",
                http_status=500
            )
        
        # ایجاد context
        from app.core.auth_dependency import AuthContext
        return AuthContext(user=system_user, db=self.db)
    
    def _make_decision(
        self,
        spam_result: Dict[str, Any],
        profanity_result: Dict[str, Any],
        ai_result: Optional[Dict[str, Any]]
    ) -> tuple[str, Decimal]:
        """
        تصمیم‌گیری نهایی براساس نتایج مختلف
        
        Returns:
            (decision, confidence)
        """
        # اگر محتوای نامناسب دارد، فوراً رد می‌شود
        if profanity_result["has_profanity"]:
            return ("reject", Decimal("95.0"))
        
        # اگر spam score بالا باشد، رد می‌شود
        if spam_result["score"] > 70:
            return ("reject", Decimal("90.0"))
        
        # اگر spam score متوسط، نیاز به بررسی دارد
        if spam_result["score"] > 40:
            confidence = Decimal("70.0")
            
            # اگر AI هم تایید کرد که spam است، رد می‌شود
            if ai_result and ai_result.get("is_spam"):
                return ("reject", Decimal("85.0"))
            
            return ("review_required", confidence)
        
        # بررسی نتیجه AI
        if ai_result:
            ai_conf = ai_result.get("confidence", 60)
            
            # اگر AI تشخیص داد محتوا مشکل دارد
            if ai_result.get("is_promotional") or ai_result.get("is_spam"):
                if ai_conf > 80:
                    return ("reject", Decimal(str(ai_conf)))
                else:
                    return ("review_required", Decimal(str(ai_conf)))
            
            # اگر AI تایید کرد محتوا مناسب است
            if ai_conf > 85 and ai_result.get("matches_event_type"):
                return ("approve", Decimal(str(ai_conf)))
        
        # پیش‌فرض: تایید با اطمینان متوسط
        # (در صورت عدم مشکل جدی، اما بهتر است مدیر یک نگاه بیندازد)
        if spam_result["score"] < 20:
            return ("approve", Decimal("75.0"))
        else:
            return ("review_required", Decimal("65.0"))
    
    def _generate_suggestions(
        self,
        flags: List[str],
        ai_result: Optional[Dict[str, Any]]
    ) -> Optional[str]:
        """تولید پیشنهادات بهبود"""
        suggestions = []
        
        # پیشنهادات براساس flags
        if any("تبلیغاتی" in flag for flag in flags):
            suggestions.append("• از کلمات تبلیغاتی مانند 'تخفیف ویژه'، 'فقط امروز' استفاده نکنید")
        
        if any("لینک" in flag for flag in flags):
            suggestions.append("• تعداد لینک‌ها را کاهش دهید")
        
        if any("علامت تعجب" in flag for flag in flags):
            suggestions.append("• از علامت تعجب کمتر استفاده کنید")
        
        # پیشنهادات AI
        if ai_result and ai_result.get("suggestions"):
            suggestions.append(f"• {ai_result['suggestions']}")
        
        return "\n".join(suggestions) if suggestions else None


class AIContentModerationService:
    """
    سرویس اصلی بررسی خودکار محتوا
    """
    
    def __init__(self):
        self.spam_detector = SpamDetector()
        self.profanity_detector = ProfanityDetector()
        # SimpleLLMClient will be implemented later
        self.llm_client = None  # SimpleLLMClient()
    
    async def review_template(
        self,
        content: str,
        subject: Optional[str],
        event_type: str
    ) -> ModerationResult:
        """
        بررسی کامل یک قالب
        
        این تابع تمام بررسی‌ها را انجام می‌دهد و تصمیم نهایی می‌گیرد
        """
        # بررسی‌های پایه
        base_checks = self._basic_checks(content)
        
        # تشخیص Spam
        spam_result = self.spam_detector.analyze(content)
        
        # بررسی محتوای نامناسب
        profanity_result = self.profanity_detector.check(content)
        
        # بررسی با LLM (اگر در دسترس باشد)
        llm_result = None
        if self.llm_client and hasattr(self.llm_client, 'is_available') and self.llm_client.is_available:
            try:
                llm_result = await self._llm_review(content, subject, event_type)
            except Exception as e:
                logger.error(f"Error in LLM review: {e}")
        
        # تصمیم‌گیری
        flags = []
        flags.extend(base_checks.get("issues", []))
        flags.extend(spam_result.get("flags", []))
        flags.extend(profanity_result.get("flags", []))
        
        decision, confidence = self._make_decision(
            spam_result, profanity_result, llm_result
        )
        
        suggestions = self._generate_suggestions(flags, llm_result)
        
        details = {
            "basic_checks": base_checks,
            "spam_check": spam_result,
            "profanity_check": profanity_result,
            "llm_review": llm_result
        }
        
        return ModerationResult(
            decision=decision,
            confidence=confidence,
            flags=flags,
            suggestions=suggestions,
            details=details
        )
    
    def _basic_checks(self, content: str) -> Dict[str, Any]:
        """بررسی‌های اولیه"""
        issues = []
        
        if len(content) < 10:
            issues.append("محتوا خیلی کوتاه است (حداقل 10 کاراکتر)")
        
        if len(content) > 1000:
            issues.append("محتوا خیلی طولانی است (حداکثر 1000 کاراکتر)")
        
        # بررسی استفاده صحیح از متغیرها
        invalid_vars = re.findall(r'\{(?!\{)[^}]*\}(?!\})', content)
        if invalid_vars:
            issues.append("استفاده نادرست از متغیر: باید از {{ variable }} استفاده کنید")
        
        return {
            "passed": len(issues) == 0,
            "issues": issues
        }
    
    async def _llm_review(
        self,
        content: str,
        subject: Optional[str],
        event_type: str
    ) -> Dict[str, Any]:
        """بررسی با LLM"""
        prompt = f"""تو یک سیستم بررسی محتوای پیامک و ایمیل کسب‌وکارها هستی.

نوع رویداد: {event_type}
موضوع: {subject or "ندارد"}

محتوا:
```
{content}
```

آیا این محتوا:
1. تبلیغاتی است؟
2. spam است؟
3. نامناسب است؟
4. با نوع رویداد مطابقت دارد؟

پاسخ را فقط JSON بده:
{{"is_promotional": true/false, "is_spam": true/false, "is_inappropriate": true/false, "matches_event_type": true/false, "confidence": 0-100, "explanation": "توضیح", "suggestions": "پیشنهاد"}}"""
        
        response_text = await self.llm_client.generate(prompt)
        
        try:
            json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
            if json_match:
                return json.loads(json_match.group(0))
        except:
            pass
        
        return {}
    
    def _make_decision(
        self,
        spam_result: Dict[str, Any],
        profanity_result: Dict[str, Any],
        llm_result: Optional[Dict[str, Any]]
    ) -> tuple[str, Decimal]:
        """تصمیم‌گیری نهایی"""
        
        # رد اگر محتوای نامناسب دارد
        if profanity_result["has_profanity"]:
            return ("reject", Decimal("95.0"))
        
        # رد اگر spam score بسیار بالا
        if spam_result["score"] > 70:
            return ("reject", Decimal("90.0"))
        
        # نیاز به بررسی اگر spam score متوسط
        if spam_result["score"] > 40:
            if llm_result and llm_result.get("is_spam"):
                return ("reject", Decimal("85.0"))
            return ("review_required", Decimal("70.0"))
        
        # بررسی LLM
        if llm_result:
            llm_conf = llm_result.get("confidence", 60)
            
            if llm_result.get("is_promotional") or llm_result.get("is_spam"):
                if llm_conf > 80:
                    return ("reject", Decimal(str(llm_conf)))
                return ("review_required", Decimal(str(llm_conf)))
            
            if llm_conf > 90 and llm_result.get("matches_event_type"):
                return ("approve", Decimal(str(llm_conf)))
        
        # تایید با اطمینان متوسط
        if spam_result["score"] < 20:
            return ("approve", Decimal("80.0"))
        
        return ("review_required", Decimal("65.0"))
    
    def _generate_suggestions(
        self,
        flags: List[str],
        ai_result: Optional[Dict[str, Any]]
    ) -> Optional[str]:
        """تولید پیشنهادات"""
        suggestions = []
        
        if any("تبلیغاتی" in flag for flag in flags):
            suggestions.append("از کلمات تبلیغاتی استفاده نکنید")
        
        if any("لینک" in flag for flag in flags):
            suggestions.append("تعداد لینک‌ها را کاهش دهید")
        
        if ai_result and ai_result.get("suggestions"):
            suggestions.append(ai_result["suggestions"])
        
        return "\n".join(suggestions) if suggestions else None

