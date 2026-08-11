# ممیزی گزارشات حسابیکس از منظر چندارزی

**تاریخ ممیزی اولیه:** ۱۴۰۵/۰۵/۱۹  
**به‌روزرسانی فاز ۱ (اصلاحات + Aging/CFS/تسعیر):** ۱۴۰۵/۰۵/۱۹  
**به‌روزرسانی فاز ۲ (پیشنهادهای بعدی):** ۱۴۰۵/۰۵/۱۹  
**به‌روزرسانی فاز ۳ (تکمیل باقیمانده):** ۱۴۰۵/۰۵/۱۹  

**محدوده:** [`/business/{id}/…/reports`](https://arc.hesabix.ir/business/6262/tab0/reports)  
**منبع فهرست:** `hesabixUI/.../pages/business/reports_page.dart`

---

## ۱. خلاصه وضعیت فعلی

| موضوع | وضعیت |
|------|--------|
| قرارداد چندارزی | `currency_id=null` → همه ارزها (معادل پایه)؛ با ارز → بومی همان ارز |
| صورت‌های مالی | ✅ پایه + دوستونه (بومی+پایه) روی TB / PnL / **ترازنامه / بسته مالی** |
| اشخاص | ✅ بدهکار/بستانکار/معین/اقساط/Aging + مانده به تفکیک ارز |
| جریان وجوه | ✅ مستقیم (IAS 7 طرف مقابل) + **روش غیرمستقیم از سود خالص** |
| کیفیت داده FX | ✅ هشدار خطوط بدون `*_base` در meta + بنر UI |
| کاردکس اسناد | ✅ فیلتر ارز + نمایش معادل پایه |
| امتیاز تقریبی | صورت‌های مالی/اشخاص ≈ **۹۰–۹۵٪**؛ عملیاتی ≈ **۸۵٪** |

---

## ۲. قرارداد حسابداری چندارزی

| حالت | Backend | UI |
|------|---------|-----|
| بدون ارز | `*_base` / تبدیل نرخ | همه ارزها (معادل پایه) |
| با ارز | فیلتر سند + مبالغ بومی | کد ارز |
| دوستونه | `include_base_equivalent=true` + ارز مشخص → ستون‌های بومی + `*_base` / `amount_base` | سوئیچ «نمایش معادل پایه» |
| مانده per-currency | بومی هر ارز + `base_equivalent` | گزارش اختصاصی |
| CFS غیرمستقیم | `include_indirect=true` → `indirect_operating` | کارت جدا + bridge با روش مستقیم |

---

## ۳. تغییرات فاز ۳ (این مرحله)

### ۳.۱ دوستونه ترازنامه و بسته مالی
- `include_base_equivalent` در `balance_sheet_service` و `financial_package_service`
- API: body ترازنامه/خروجی بسته مالی
- UI: سوئیچ + ستون «معادل پایه» روی ترازنامه و بسته مالی

### ۳.۲ صورت جریان — روش غیرمستقیم (IAS 7)
- از سود خالص + استهلاک انباشته (۱۰۸) + Δ دریافتنی (۱۰۴) + Δ موجودی (۱۰۵) + Δ پرداختنی (۲۰۱/۲۰۲)
- کلید `indirect_operating` با `bridge_difference` نسبت به جریان عملیاتی مستقیم
- UI: فیلتر «روش غیرمستقیم» + کارت reconciliation

### ۳.۳ کیفیت داده چندارزی
- سرویس: `fx_data_quality_service.get_missing_base_amount_warnings`
- تزریق به `meta.fx_data_quality` در تراز آزمایشی، ترازنامه، جریان وجوه
- ویجت: `FxDataQualityBanner` روی صفحات کلیدی

### ۳.۴ یکدست‌سازی برچسب/فیلتر ارز
- `ReportCurrencyFilterDropdown` روی ترازنامه، جریان وجوه، بسته مالی
- برچسب استاندارد «همه ارزها (معادل پایه)» روی رتبه‌بندی مشتری/تأمین‌کننده، PnL مشترک، تراز آزمایشی

### ۳.۵ تست‌ها
- `tests/test_reports_multi_currency_phase3.py`

---

## ۴. ماتریس گزارشات (خلاصه)

| دسته | وضعیت MC |
|------|----------|
| تراز/ترازنامه/بسته/دفاتر/مرور/PnL | ✅ (+ dual اختیاری) |
| بدهکار/بستانکار/معین/اقساط/Aging×۲ / مانده per-currency | ✅ |
| فروش/خرید/تولید/رتبه‌بندی | ✅ تجمیع به پایه |
| بانک/صندوق/چک | ✅ |
| ارزش موجودی | ✅ ارز پایه |
| جریان وجوه (مستقیم+غیرمستقیم) / تسعیر | ✅ |
| کاردکس اسناد | ✅ فیلتر ارز |
| انبار مقداری / سیستم / کانکتور | ⚪ |
| HScript | 🟡 سفارشی |

---

## ۵. باقیمانده اختیاری (خارج از این فاز)

1. مهاجرت تک‌تک صفحات قدیمی به `ReportCurrencyFilterDropdown` + `MultiCurrencyGate` مبتنی بر AuthStore (بخشی انجام شد)
2. تست integration با DB واقعی برای Aging/CFS end-to-end
3. گسترش تعدیلات غیرمستقیم (مالیات معوق، سود تسعیر غیرنقدی تفصیلی، …)

---

## ۶. فایل‌های کلیدی فاز ۳

**Backend:**  
`balance_sheet_service.py`, `financial_package_service.py`, `cash_flow_report_service.py`, `fx_data_quality_service.py`, `trial_balance_service.py`, `documents.py`, `tests/test_reports_multi_currency_phase3.py`

**UI:**  
`balance_sheet_report_page.dart`, `balance_sheet_report_shared.dart`, `cash_flow_report_page.dart`, `financial_reports_package_page.dart`, `fx_data_quality_banner.dart`, `report_currency_filter_dropdown.dart`

---

*پایان نسخه فاز ۳.*
