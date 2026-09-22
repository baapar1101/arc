---
description: پیشرفت انطباق M3 نسبت به baseline
allowed-tools: Bash(dart run tool/m3_audit.dart:*), Bash(cat tool/m3_baseline.json), Bash(git log:*), Bash(git status:*), Read
---

وضعیت فعلی:

```
!`dart run tool/m3_audit.dart 2>&1 | tail -40`
```

baseline ثبت‌شده:

```
!`cat tool/m3_baseline.json`
```

کارهای انجام‌شده روی این برنچ:

```
!`git log --oneline master..HEAD 2>/dev/null | head -20`
```

یک جدول بده: هر قانون، عدد baseline، عدد فعلی، درصد پیشرفت.
بعد بگو منطقی‌ترین قانون بعدی برای کار کدام است و چرا — ملاک:
شدت BLOCKER اول، بعد نسبت «تعداد تخلف به تعداد فایل» (تخلف متمرکز
در فایل‌های کم، سریع‌تر تمام می‌شود).
