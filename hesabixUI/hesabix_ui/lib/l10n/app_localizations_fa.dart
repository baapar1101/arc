// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'حسابیکس';

  @override
  String get login => 'ورود';

  @override
  String get username => 'نام کاربری';

  @override
  String get password => 'رمز عبور';

  @override
  String get submit => 'ثبت';

  @override
  String get loginFailed => 'ورود ناموفق بود. لطفاً دوباره تلاش کنید.';

  @override
  String get homeWelcome => 'ورود موفقیت‌آمیز!';

  @override
  String get language => 'زبان';

  @override
  String get requiredField => 'ضروری است';

  @override
  String get register => 'عضویت';

  @override
  String get forgotPassword => 'فراموشی رمز';

  @override
  String get firstName => 'نام';

  @override
  String get lastName => 'نام خانوادگی';

  @override
  String get email => 'ایمیل';

  @override
  String get mobile => 'شماره موبایل';

  @override
  String get registerSuccess => 'عضویت با موفقیت انجام شد.';

  @override
  String get forgotSent => 'لینک بازیابی به ایمیل ارسال شد.';

  @override
  String get identifier => 'ایمیل یا شماره موبایل';

  @override
  String get theme => 'تم';

  @override
  String get system => 'سیستمی';

  @override
  String get light => 'روشن';

  @override
  String get dark => 'تیره';

  @override
  String get welcomeTitle => 'حسابداری ابری حسابیکس';

  @override
  String get welcomeSubtitle =>
      'حسابداری هوشمند، امن و همیشه در دسترس برای کسب‌وکار شما.';

  @override
  String get brandTagline => 'مدیریت مالی هرجا و هر زمان با اطمینان.';

  @override
  String get captcha => 'کد امنیتی';

  @override
  String get refresh => 'تازه‌سازی';

  @override
  String get captchaRequired => 'کد امنیتی الزامی است.';
}
