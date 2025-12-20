import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/calendar_controller.dart';
import '../core/auth_store.dart';
import '../core/locale_controller.dart';
import '../core/referral_store.dart';
import '../theme/theme_controller.dart';
import '../utils/number_normalizer.dart';
import '../widgets/auth_footer.dart';
import '../../utils/snackbar_helper.dart';
import '../utils/responsive_helper.dart';
import '../services/otp_login_service.dart';
import '../services/password_reset_otp_service.dart';
import '../services/errors/api_error.dart';
import '../widgets/auth/otp_input_dialog.dart';

class LoginPage extends StatefulWidget {
  final LocaleController localeController;
  final CalendarController calendarController;
  final ThemeController? themeController;
  final AuthStore authStore;
  const LoginPage({super.key, required this.localeController, required this.calendarController, this.themeController, required this.authStore});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  // Login
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _loginCaptchaCtrl = TextEditingController();
  String? _loginCaptchaId;
  Uint8List? _loginCaptchaImage;
  Timer? _loginCaptchaTimer;
  bool _loadingLogin = false;

  // Register
  final _registerKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _registerPasswordCtrl = TextEditingController();
  final _registerCaptchaCtrl = TextEditingController();
  String? _registerCaptchaId;
  Uint8List? _registerCaptchaImage;
  bool _loadingRegister = false;
  Timer? _registerCaptchaTimer;

  // Forgot password
  final _forgotKey = GlobalKey<FormState>();
  final _forgotIdentifierCtrl = TextEditingController();
  final _forgotCaptchaCtrl = TextEditingController();
  String? _forgotCaptchaId;
  Uint8List? _forgotCaptchaImage;
  bool _loadingForgot = false;
  Timer? _forgotCaptchaTimer;

  // OTP Login
  final _otpLoginKey = GlobalKey<FormState>();
  final _otpLoginIdentifierCtrl = TextEditingController();
  final _otpLoginCaptchaCtrl = TextEditingController();
  String? _otpLoginCaptchaId;
  Uint8List? _otpLoginCaptchaImage;
  Timer? _otpLoginCaptchaTimer;
  String? _otpLoginSessionId;
  String? _selectedChannel;
  List<String> _availableChannels = [];
  bool _loadingOtpLogin = false;
  bool _loadingChannels = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _registerPasswordCtrl.dispose();
    _registerCaptchaCtrl.dispose();
    _forgotIdentifierCtrl.dispose();
    _loginCaptchaCtrl.dispose();
    _forgotCaptchaCtrl.dispose();
    _loginCaptchaTimer?.cancel();
    _registerCaptchaTimer?.cancel();
    _forgotCaptchaTimer?.cancel();
    _otpLoginIdentifierCtrl.dispose();
    _otpLoginCaptchaCtrl.dispose();
    _otpLoginCaptchaTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCaptcha(String scope) async {
    try {
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>('/api/v1/auth/captcha');
      final body = res.data;
      if (body is! Map<String, dynamic>) return;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return;
      final String? id = data['captcha_id']?.toString();
      final String? imgB64 = data['image_base64']?.toString();
      final int? ttl = (data['ttl_seconds'] as num?)?.toInt();
      if (id == null || imgB64 == null) return;
      Uint8List bytes;
      try {
        bytes = base64Decode(imgB64);
      } catch (_) {
        return;
      }
      if (!mounted) return;
      setState(() {
        if (scope == 'login') _loginCaptchaId = id;
        if (scope == 'register') _registerCaptchaId = id;
        if (scope == 'forgot') _forgotCaptchaId = id;
        if (scope == 'otpLogin') _otpLoginCaptchaId = id;
        if (scope == 'login') _loginCaptchaImage = bytes;
        if (scope == 'register') _registerCaptchaImage = bytes;
        if (scope == 'forgot') _forgotCaptchaImage = bytes;
        if (scope == 'otpLogin') _otpLoginCaptchaImage = bytes;
      });
      if (ttl != null && ttl > 0) {
        final delay = Duration(seconds: ttl);
        if (scope == 'login') {
          _loginCaptchaTimer?.cancel();
          _loginCaptchaTimer = Timer(delay, () => _refreshCaptcha('login'));
        } else if (scope == 'register') {
          _registerCaptchaTimer?.cancel();
          _registerCaptchaTimer = Timer(delay, () => _refreshCaptcha('register'));
        } else         if (scope == 'forgot') {
          _forgotCaptchaTimer?.cancel();
          _forgotCaptchaTimer = Timer(delay, () => _refreshCaptcha('forgot'));
        } else if (scope == 'otpLogin') {
          _otpLoginCaptchaTimer?.cancel();
          _otpLoginCaptchaTimer = Timer(delay, () => _refreshCaptcha('otpLogin'));
        }
      }
    } catch (_) {
      // سکوت: خطای شبکه/شکل پاسخ نباید باعث کرش شود
    }
  }

  @override
  void initState() {
    super.initState();
    // پیش‌بارگذاری کپچا برای هر چهار تب
    _refreshCaptcha('login');
    _refreshCaptcha('register');
    _refreshCaptcha('forgot');
    _refreshCaptcha('otpLogin');
    // ذخیره کد معرف از URL (اگر وجود داشت)
    unawaited(ReferralStore.captureFromCurrentUrl());
  }

  String _extractErrorMessage(Object e, AppLocalizations t) {
    try {
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          final err = data['error'] is Map ? data['error'] as Map : null;
          List<dynamic>? details;
          if (err != null && err['details'] is List) {
            details = err['details'] as List;
          } else if (data['detail'] is List) {
            details = data['detail'] as List;
          }
          if (details != null && details.isNotEmpty) {
            final parts = <String>[];
            for (final item in details) {
              if (item is Map) {
                final fieldRaw = (item['field'] ?? (item['loc'] is List ? (item['loc'] as List).isNotEmpty ? (item['loc'] as List).last?.toString() : null : null))?.toString();
                final String? message = (item['message'] ?? item['msg'])?.toString();
                String label = '';
                switch (fieldRaw) {
                  case 'password':
                    label = t.password;
                    break;
                  case 'email':
                    label = t.email;
                    break;
                  case 'mobile':
                    label = t.mobile;
                    break;
                  case 'first_name':
                    label = t.firstName;
                    break;
                  case 'last_name':
                    label = t.lastName;
                    break;
                  case 'captcha':
                  case 'captcha_code':
                    label = t.captcha;
                    break;
                  case 'identifier':
                    label = t.identifier;
                    break;
                  default:
                    label = fieldRaw ?? '';
                }
                if (message != null && message.isNotEmpty) {
                  parts.add(label.isNotEmpty ? '$label: $message' : message);
                }
              }
            }
            if (parts.isNotEmpty) {
              return parts.join('\n');
            }
          }
          if (err != null && err['message'] is String) {
            return err['message'] as String;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }

  Future<void> _loadAvailableChannels() async {
    final identifier = toEnglishDigits(_otpLoginIdentifierCtrl.text.trim());
    if (identifier.isEmpty) {
      setState(() {
        _availableChannels = [];
        _selectedChannel = null;
      });
      return;
    }

    setState(() {
      _loadingChannels = true;
    });

    try {
      final service = OtpLoginService(ApiClient());
      final result = await service.getAvailableChannels(identifier);
      
      if (!mounted) return;
      
      final channels = (result['available_channels'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      
      setState(() {
        _availableChannels = channels;
        if (channels.isNotEmpty && !channels.contains(_selectedChannel)) {
          _selectedChannel = channels.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      // خطا را نادیده می‌گیریم - کاربر می‌تواند ادامه دهد
    } finally {
      if (mounted) {
        setState(() {
          _loadingChannels = false;
        });
      }
    }
  }

  Future<void> _sendOtpLogin({bool changeChannel = false}) async {
    final form = _otpLoginKey.currentState;
    if (form == null || !form.validate()) return;
    
    if (_selectedChannel == null || _selectedChannel!.isEmpty) {
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).otpSelectChannelError);
      return;
    }
    
    if ((_otpLoginCaptchaCtrl.text.trim().isEmpty) || (_otpLoginCaptchaId == null)) {
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).captchaRequired);
      return;
    }

    setState(() {
      _loadingOtpLogin = true;
    });

    try {
      final service = OtpLoginService(ApiClient());
      final identifier = toEnglishDigits(_otpLoginIdentifierCtrl.text.trim());
      final result = await service.sendLoginOtp(
        identifier: identifier,
        channel: _selectedChannel!,
        captchaId: _otpLoginCaptchaId!,
        captchaCode: toEnglishDigits(_otpLoginCaptchaCtrl.text.trim()),
        sessionId: changeChannel ? _otpLoginSessionId : null,
      );
      
      if (!mounted) return;
      
      final sessionId = result['session_id']?.toString();
      final availableChannels = (result['available_channels'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      
      if (sessionId != null && sessionId.isNotEmpty) {
        setState(() {
          _otpLoginSessionId = sessionId;
          _availableChannels = availableChannels;
        });
        
        final t = AppLocalizations.of(context);
        final channelNames = {
          'sms': t.otpChannelSms,
          'email': t.otpChannelEmail,
          'telegram': t.otpChannelTelegram,
        };
        final channelName = channelNames[_selectedChannel] ?? _selectedChannel ?? '';
        SnackBarHelper.show(context, message: t.otpCodeSentMessage(channelName));
        
        // نمایش Dialog برای وارد کردن OTP
        final verified = await showDialog<bool>(
          context: context,
          builder: (ctx) => OtpInputDialog(
            title: AppLocalizations.of(context).otpLoginTitle,
            message: 'کد 6 رقمی ارسال شده را وارد کنید',
            onVerify: (otp) async {
              try {
                final verifyResult = await service.verifyLoginOtp(
                  sessionId: sessionId,
                  otpCode: otp,
                  deviceId: widget.authStore.deviceId,
                );
                
                final apiKey = verifyResult['api_key']?.toString();
                final user = verifyResult['user'] as Map<String, dynamic>?;
                
                if (apiKey != null && apiKey.isNotEmpty) {
                  await widget.authStore.saveApiKey(apiKey);
                  
                  // ذخیره اطلاعات کاربر
                  final appPermissions = user?['app_permissions'] as Map<String, dynamic>?;
                  final isSuperAdmin = appPermissions?['superadmin'] == true;
                  final userId = user?['id'] as int?;
                  final referralCode = user?['referral_code']?.toString();
                  
                  String? userName;
                  if (user != null) {
                    final firstName = user['first_name']?.toString()?.trim();
                    final lastName = user['last_name']?.toString()?.trim();
                    if (firstName != null || lastName != null) {
                      userName = [firstName, lastName].where((e) => e != null && e.isNotEmpty).join(' ');
                    }
                  }
                  
                  if (appPermissions != null) {
                    await widget.authStore.saveAppPermissions(
                      appPermissions,
                      isSuperAdmin,
                      userId: userId,
                      userName: userName,
                    );
                  }
                  
                  if (referralCode != null) {
                    unawaited(ReferralStore.saveUserReferralCode(referralCode));
                  }
                  
                  if (!mounted) return true;
                  SnackBarHelper.show(context, message: AppLocalizations.of(context).homeWelcome);
                  
                  // هدایت به dashboard
                  context.go('/user/profile/dashboard');
                  return true;
                }
                return false;
              } catch (e) {
                // استخراج پیام خطای مناسب از ApiErrorDetails
                String errorMessage = 'خطا در ورود';
                if (e is DioException && e.error is ApiErrorDetails) {
                  final apiError = e.error as ApiErrorDetails;
                  errorMessage = apiError.message ?? errorMessage;
                } else if (e is ApiErrorDetails) {
                  errorMessage = e.message ?? errorMessage;
                } else {
                  errorMessage = 'خطا در ورود: $e';
                }
                
                SnackBarHelper.showError(context, message: errorMessage);
                return false;
              }
            },
            onResend: () async {
              try {
                // استفاده از همان کپتچای قبلی یا refresh در صورت نیاز
                final t = AppLocalizations.of(context);
                if (_otpLoginCaptchaId == null) {
                  await _refreshCaptcha('otpLogin');
                  if (_otpLoginCaptchaId == null) {
                    SnackBarHelper.showError(context, message: t.otpCaptchaError);
                    return;
                  }
                }
                
                final captchaCode = _otpLoginCaptchaCtrl.text.trim();
                if (captchaCode.isEmpty) {
                  SnackBarHelper.showError(context, message: t.otpEnterCaptchaError);
                  return;
                }
                
                final identifier = toEnglishDigits(_otpLoginIdentifierCtrl.text.trim());
                final resendResult = await service.sendLoginOtp(
                  identifier: identifier,
                  channel: _selectedChannel!,
                  captchaId: _otpLoginCaptchaId!,
                  captchaCode: toEnglishDigits(captchaCode),
                  sessionId: sessionId,
                );
                final newSessionId = resendResult['session_id']?.toString();
                if (newSessionId != null) {
                  setState(() {
                    _otpLoginSessionId = newSessionId;
                  });
                  SnackBarHelper.show(context, message: AppLocalizations.of(context).otpCodeResentMessage);
                }
              } catch (e) {
                // استخراج پیام خطای مناسب از ApiErrorDetails
                String errorMessage = 'خطا در ارسال مجدد کد';
                if (e is DioException && e.error is ApiErrorDetails) {
                  final apiError = e.error as ApiErrorDetails;
                  errorMessage = apiError.message ?? errorMessage;
                } else if (e is ApiErrorDetails) {
                  errorMessage = e.message ?? errorMessage;
                } else {
                  errorMessage = 'خطا در ارسال مجدد کد: $e';
                }
                
                SnackBarHelper.showError(context, message: errorMessage);
              }
            },
          ),
        );
        
        if (verified == true && mounted) {
          // ورود موفق - صفحه بسته می‌شود
          Navigator.of(context).pop();
        }
      } else {
        SnackBarHelper.showError(context, message: 'خطا در ارسال کد ورود');
      }
    } catch (e) {
      if (!mounted) return;
      
      // استخراج پیام خطای مناسب از ApiErrorDetails
      final t = AppLocalizations.of(context);
      String errorMessage = t.otpSendError;
      if (e is DioException && e.error is ApiErrorDetails) {
        final apiError = e.error as ApiErrorDetails;
        errorMessage = apiError.message ?? errorMessage;
      } else if (e is ApiErrorDetails) {
        errorMessage = e.message ?? errorMessage;
      } else {
        errorMessage = 'خطا در ارسال کد: $e';
      }
      
      SnackBarHelper.showError(context, message: errorMessage);
      // در صورت خطا، کپتچا را refresh می‌کنیم
      if (mounted) {
        setState(() {
          _otpLoginCaptchaCtrl.clear();
        });
        _refreshCaptcha('otpLogin');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingOtpLogin = false;
        });
      }
    }
  }

  Future<void> _onSubmit() async {
    final form = _formKey.currentState;
    final t = AppLocalizations.of(context);
    if (form == null || !form.validate()) return;
    if ((_loginCaptchaCtrl.text.trim().isEmpty) || (_loginCaptchaId == null)) {
      SnackBarHelper.show(context, message: t.captchaRequired);
      return;
    }

    setState(() {
      _loadingLogin = true;
    });

    try {
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: {
          'identifier': _identifierCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'captcha_id': _loginCaptchaId,
          'captcha_code': _loginCaptchaCtrl.text.trim(),
          'device_id': widget.authStore.deviceId,
          'referrer_code': await ReferralStore.getReferrerCode(),
        },
      );
      Map<String, dynamic>? data;
      final body = res.data;
      if (body is Map<String, dynamic>) {
        final inner = body['data'];
        if (inner is Map<String, dynamic>) data = inner;
      }
      final apiKey = data != null ? data['api_key']?.toString() : null;
      if (apiKey != null && apiKey.isNotEmpty) {
        await widget.authStore.saveApiKey(apiKey);
      }
      
      // ذخیره کد بازاریابی کاربر برای صفحه Marketing
      final user = data?['user'] as Map<String, dynamic>?;
      final String? myRef = user != null ? user['referral_code']?.toString() : null;
      unawaited(ReferralStore.saveUserReferralCode(myRef));
      
      // ذخیره دسترسی‌های اپلیکیشن و اطلاعات کاربر برای نمایش در منو
      final appPermissions = user?['app_permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = appPermissions?['superadmin'] == true;
      final userId = user?['id'] as int?;
      String? userName;
      String? userMobile;
      if (user != null) {
        final fullName = user['full_name']?.toString().trim();
        final firstName = user['first_name']?.toString().trim();
        final lastName = user['last_name']?.toString().trim();
        if (fullName != null && fullName.isNotEmpty) {
          userName = fullName;
        } else {
          final buffer = <String>[];
          if (firstName != null && firstName.isNotEmpty) buffer.add(firstName);
          if (lastName != null && lastName.isNotEmpty) buffer.add(lastName);
          if (buffer.isNotEmpty) {
            userName = buffer.join(' ');
          } else {
            final email = user['email']?.toString().trim();
            if (email != null && email.isNotEmpty) {
              userName = email;
            }
          }
        }
        final mobile = user['mobile']?.toString().trim();
        if (mobile != null && mobile.isNotEmpty) {
          userMobile = mobile;
        }
      }
      if (appPermissions != null) {
        await widget.authStore.saveAppPermissions(
          appPermissions,
          isSuperAdmin,
          userId: userId,
          userName: userName,
          userMobile: userMobile,
        );
      }

      if (!mounted) return;
      _showSnack(t.homeWelcome);
      // بعد از login موفق، به صفحه قبلی یا dashboard برود
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        if (currentPath.startsWith('/user/profile/') || currentPath.startsWith('/acc/') || currentPath.startsWith('/business/')) {
          // اگر در صفحه محافظت شده بود، همان صفحه را refresh کند
          context.go(currentPath);
        } else {
          // وگرنه به dashboard برود
          context.go('/user/profile/dashboard');
        }
      } catch (e) {
        // اگر GoRouterState در دسترس نیست، به dashboard برود
        context.go('/user/profile/dashboard');
      }
    } catch (e) {
      final msg = _extractErrorMessage(e, AppLocalizations.of(context));
      _showSnack(msg);
      setState(() {
        _loginCaptchaCtrl.clear();
      });
      // فقط اسنک‌بار نمایش داده می‌شود؛ وضعیت داخلی خطا ذخیره نمی‌شود
    } finally {
      if (mounted) {
        setState(() {
          _loadingLogin = false;
        });
      }
      _refreshCaptcha('login');
    }
  }

  Future<void> _onRegister() async {
    final t = AppLocalizations.of(context);
    // اعتبارسنجی دستی و نمایش فقط Snackbar
    if (_firstNameCtrl.text.trim().isEmpty) {
      _showSnack('${t.firstName} ${t.requiredField}');
      return;
    }
    if (_lastNameCtrl.text.trim().isEmpty) {
      _showSnack('${t.lastName} ${t.requiredField}');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty && _mobileCtrl.text.trim().isEmpty) {
      final msg = '${t.email} / ${t.mobile} ${t.requiredField}';
      _showSnack(msg);
      return;
    }
    if (_registerPasswordCtrl.text.isEmpty) {
      _showSnack('${t.password} ${t.requiredField}');
      return;
    }
    if (_registerCaptchaId == null || _registerCaptchaCtrl.text.trim().isEmpty) {
      _showSnack(t.captchaRequired);
      return;
    }

    setState(() => _loadingRegister = true);
    try {
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/auth/register',
        data: {
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          'mobile': _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
          'password': _registerPasswordCtrl.text,
          'captcha_id': _registerCaptchaId,
          'captcha_code': _registerCaptchaCtrl.text.trim(),
          'device_id': widget.authStore.deviceId,
          'referrer_code': await ReferralStore.getReferrerCode(),
        },
      );

      if (!mounted) return;
      Map<String, dynamic>? data;
      final body = res.data;
      if (body is Map<String, dynamic>) {
        final inner = body['data'];
        if (inner is Map<String, dynamic>) data = inner;
      }
      final apiKey = data != null ? data['api_key']?.toString() : null;
      if (apiKey != null && apiKey.isNotEmpty) {
        await widget.authStore.saveApiKey(apiKey);
      }
      
      // ذخیره کد بازاریابی کاربر
      final user = data?['user'] as Map<String, dynamic>?;
      final String? myRef = user != null ? user['referral_code'] as String? : null;
      unawaited(ReferralStore.saveUserReferralCode(myRef));
      
      // ذخیره دسترسی‌های اپلیکیشن و اطلاعات کاربر برای نمایش در منو
      final appPermissions = user?['app_permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = appPermissions?['superadmin'] == true;
      final userId = user?['id'] as int?;
      String? userName;
      String? userMobile;
      if (user != null) {
        final fullName = user['full_name']?.toString().trim();
        final firstName = user['first_name']?.toString().trim();
        final lastName = user['last_name']?.toString().trim();
        if (fullName != null && fullName.isNotEmpty) {
          userName = fullName;
        } else {
          final buffer = <String>[];
          if (firstName != null && firstName.isNotEmpty) buffer.add(firstName);
          if (lastName != null && lastName.isNotEmpty) buffer.add(lastName);
          if (buffer.isNotEmpty) {
            userName = buffer.join(' ');
          } else {
            final email = user['email']?.toString().trim();
            if (email != null && email.isNotEmpty) {
              userName = email;
            }
          }
        }
        final mobile = user['mobile']?.toString().trim();
        if (mobile != null && mobile.isNotEmpty) {
          userMobile = mobile;
        }
      }
      if (appPermissions != null) {
        await widget.authStore.saveAppPermissions(
          appPermissions,
          isSuperAdmin,
          userId: userId,
          userName: userName,
          userMobile: userMobile,
        );
      }
      _showSnack(t.registerSuccess);
      // پاکسازی کد معرف پس از ثبت‌نام موفق
      unawaited(ReferralStore.clearReferrer());
      if (mounted) {
        context.go('/user/profile/dashboard');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _extractErrorMessage(e, AppLocalizations.of(context));
      _showSnack(msg.isEmpty ? t.registerFailed : msg);
      setState(() {
        _registerCaptchaCtrl.clear();
      });
    } finally {
      if (mounted) setState(() => _loadingRegister = false);
      _refreshCaptcha('register');
    }
  }

  Future<void> _onForgot() async {
    final t = AppLocalizations.of(context);
    // اعتبارسنجی دستی و نمایش فقط Snackbar
    if (_forgotIdentifierCtrl.text.trim().isEmpty) {
      _showSnack('${t.identifier} ${t.requiredField}');
      return;
    }
    if (_forgotCaptchaId == null || _forgotCaptchaCtrl.text.trim().isEmpty) {
      _showSnack(t.captchaRequired);
      return;
    }

    setState(() => _loadingForgot = true);
    try {
      final identifier = _forgotIdentifierCtrl.text.trim();
      // بررسی اینکه آیا شماره موبایل است یا ایمیل
      // استفاده از منطق مشابه بک‌اند برای تشخیص
      final cleaned = toEnglishDigits(identifier.trim().replaceAll(RegExp(r'[\s\-\(\)]'), ''));
      bool isMobile = false;
      
      // بررسی فرمت‌های مختلف موبایل ایرانی
      if (cleaned.contains('@')) {
        // اگر @ دارد، قطعاً ایمیل است
        isMobile = false;
      } else {
        // تبدیل به فرمت استاندارد برای بررسی
        String normalized = cleaned;
        if (normalized.startsWith('+989')) {
          normalized = '0${normalized.substring(4)}'; // +989 -> 0
        } else if (normalized.startsWith('00989')) {
          normalized = '0${normalized.substring(5)}'; // 00989 -> 0
        } else if (normalized.startsWith('989') && normalized.length >= 12) {
          normalized = '0${normalized.substring(3)}'; // 989 -> 0
        } else if (normalized.startsWith('9') && normalized.length == 10) {
          normalized = '0$normalized';
        }
        
        // بررسی فرمت نهایی (باید 0912... باشد)
        if (RegExp(r'^09\d{9}$').hasMatch(normalized)) {
          isMobile = true;
        } else if (RegExp(r'^\+989\d{9}$').hasMatch(cleaned) ||
                   RegExp(r'^00989\d{9}$').hasMatch(cleaned) ||
                   RegExp(r'^989\d{9}$').hasMatch(cleaned)) {
          isMobile = true;
        }
      }
      
      if (isMobile) {
        // استفاده از OTP برای موبایل
        final otpService = PasswordResetOtpService(ApiClient());
        final result = await otpService.sendPasswordResetOtp(
          identifier: identifier,
          captchaId: _forgotCaptchaId!,
          captchaCode: toEnglishDigits(_forgotCaptchaCtrl.text.trim()),
        );
        
        if (!mounted) return;
        
        // نمایش Dialog برای وارد کردن OTP
        final verified = await showDialog<bool>(
          context: context,
          builder: (ctx) => OtpInputDialog(
            title: 'بازیابی رمز عبور',
            message: 'کد 6 رقمی ارسال شده را وارد کنید',
            onVerify: (otp) async {
              try {
                final verifyResult = await otpService.verifyPasswordResetOtp(
                  identifier: identifier,
                  otpCode: otp,
                );
                final resetToken = verifyResult['reset_token']?.toString();
                if (resetToken != null && resetToken.isNotEmpty) {
                  // نمایش Dialog برای تغییر رمز عبور
                  return await _showResetPasswordDialog(ctx, resetToken);
                }
                return false;
              } catch (e) {
                SnackBarHelper.showError(context, message: 'خطا در تایید: $e');
                return false;
              }
            },
          ),
        );
        
        if (verified == true) {
          _showSnack('رمز عبور با موفقیت تغییر کرد');
        }
      } else {
        // استفاده از روش قدیمی (ایمیل)
        final api = ApiClient();
        final response = await api.post<Map<String, dynamic>>(
          '/api/v1/auth/forgot-password',
          data: {
            'identifier': identifier,
            'captcha_id': _forgotCaptchaId,
            'captcha_code': toEnglishDigits(_forgotCaptchaCtrl.text.trim()),
            'referrer_code': await ReferralStore.getReferrerCode(),
          },
        );

        if (!mounted) return;
        
        // بررسی اینکه آیا درخواست موفق بوده است
        final body = response.data;
        if (body is Map<String, dynamic>) {
          final data = body['data'] as Map<String, dynamic>?;
          final ok = data?['ok'] as bool?;
          if (ok == true) {
            _showSnack(t.forgotSent);
          } else {
            _showSnack('خطا در ارسال درخواست بازیابی رمز عبور');
          }
        } else {
          _showSnack(t.forgotSent);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _extractErrorMessage(e, AppLocalizations.of(context));
      _showSnack(msg);
      setState(() {
        _forgotCaptchaCtrl.clear();
      });
    } finally {
      if (mounted) setState(() => _loadingForgot = false);
      _refreshCaptcha('forgot');
    }
  }

  Future<bool> _showResetPasswordDialog(BuildContext context, String resetToken) async {
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    final captchaCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? captchaId;
    Uint8List? captchaImage;
    Timer? captchaTimer;

    // تابع برای دریافت کپچا
    Future<void> loadCaptcha() async {
      try {
        final api = ApiClient();
        final captchaRes = await api.post<Map<String, dynamic>>('/api/v1/auth/captcha');
        final captchaData = captchaRes.data?['data'] as Map<String, dynamic>?;
        final String? id = captchaData?['captcha_id']?.toString();
        final String? imgB64 = captchaData?['image_base64']?.toString();
        final int? ttl = (captchaData?['ttl_seconds'] as num?)?.toInt();
        
        if (id != null && imgB64 != null) {
          try {
            final bytes = base64Decode(imgB64);
            if (context.mounted) {
              setState(() {
                captchaId = id;
                captchaImage = bytes;
              });
              if (ttl != null && ttl > 0) {
                captchaTimer?.cancel();
                captchaTimer = Timer(Duration(seconds: ttl), () {
                  loadCaptcha();
                });
              }
            }
          } catch (_) {
            // خطا در decode
          }
        }
      } catch (_) {
        // خطا در دریافت کپچا
      }
    }

    // بارگذاری اولیه کپچا
    await loadCaptcha();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('تغییر رمز عبور'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: newPasswordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رمز عبور جدید',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'رمز عبور الزامی است';
                      }
                      if (v.length < 6) {
                        return 'رمز عبور باید حداقل 6 کاراکتر باشد';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'تکرار رمز عبور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v != newPasswordCtrl.text) {
                        return 'رمز عبور با تکرار آن مطابقت ندارد';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: captchaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'کد کپچا',
                            prefixIcon: Icon(Icons.security),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            const EnglishDigitsFormatter(),
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'کد کپچا الزامی است';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (captchaImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            captchaImage!,
                            height: 40,
                            width: 120,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        const SizedBox(height: 40, width: 120),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: saving ? null : () async {
                          await loadCaptcha();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.refresh),
                        tooltip: 'تازه‌سازی',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () {
                captchaTimer?.cancel();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                
                if (captchaId == null || captchaCtrl.text.trim().isEmpty) {
                  SnackBarHelper.showError(dialogContext, message: 'لطفاً کد کپچا را وارد کنید');
                  return;
                }
                
                setDialogState(() => saving = true);
                try {
                  final api = ApiClient();
                  
                  await api.post<Map<String, dynamic>>(
                    '/api/v1/auth/reset-password',
                    data: {
                      'token': resetToken,
                      'new_password': newPasswordCtrl.text,
                      'captcha_id': captchaId!,
                      'captcha_code': toEnglishDigits(captchaCtrl.text.trim()),
                    },
                  );
                  
                  if (dialogContext.mounted) {
                    captchaTimer?.cancel();
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    final msg = _extractErrorMessage(e, AppLocalizations.of(dialogContext));
                    SnackBarHelper.showError(dialogContext, message: msg.isNotEmpty ? msg : 'خطا در تغییر رمز عبور: $e');
                    // تازه‌سازی کپچا در صورت خطا
                    await loadCaptcha();
                    setDialogState(() {
                      captchaCtrl.clear();
                    });
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                  }
                }
              },
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تغییر رمز عبور'),
            ),
          ],
        ),
      ),
    );

    captchaTimer?.cancel();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    captchaCtrl.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String logoAsset = isDark
        ? 'assets/images/logo-light.png'
        : 'assets/images/logo-blue.png';
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomInset + 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveHelper.getCardMaxWidth(context),
                      minHeight: constraints.maxHeight - 32, // to keep card vertically centered when possible
                    ),
                    child: Card(
                      elevation: 2,
                      margin: EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 8 : 16),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Image.asset(logoAsset, height: 28),
                                const SizedBox(width: 8),
                                Text(t.welcomeTitle, style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(t.welcomeSubtitle, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            TabBar(
                              isScrollable: true,
                              tabs: [
                                Tab(text: t.login),
                                Tab(text: t.register),
                                Tab(text: t.forgotPassword),
                                Tab(text: t.otpLogin),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Builder(builder: (innerContext) {
                              final tabController = DefaultTabController.maybeOf(innerContext);
                              if (tabController == null) {
                                return const SizedBox.shrink();
                              }
                              return AnimatedBuilder(
                                animation: tabController,
                                builder: (context, _) {
                                final idx = tabController.index;
                                Widget body;
                                if (idx == 0) {
                                  body = Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Stack(
                                      children: [
                                        AbsorbPointer(
                                          absorbing: _loadingLogin,
                                          child: Form(
                                            key: _formKey,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                TextFormField(
                                                  controller: _identifierCtrl,
                                                  decoration: InputDecoration(labelText: t.identifier),
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.identifier} ${t.requiredField}' : null,
                                                  textInputAction: TextInputAction.next,
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _passwordCtrl,
                                                  decoration: InputDecoration(labelText: t.password),
                                                  obscureText: true,
                                                  validator: (v) => (v == null || v.isEmpty) ? '${t.password} ${t.requiredField}' : null,
                                                  onFieldSubmitted: (_) => _onSubmit(),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: _loginCaptchaCtrl,
                                                        decoration: InputDecoration(labelText: t.captcha),
                                                        validator: (v) => (v == null || v.trim().isEmpty) ? '${t.captcha} ${t.requiredField}' : null,
                                                        keyboardType: TextInputType.number,
                                                        inputFormatters: [
                                                          const EnglishDigitsFormatter(),
                                                          FilteringTextInputFormatter.digitsOnly,
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    if (_loginCaptchaImage != null)
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Image.memory(
                                                          _loginCaptchaImage!,
                                                          height: 40,
                                                          width: 120,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      )
                                                    else
                                                      const SizedBox(height: 40, width: 120),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: _loadingLogin ? null : () => _refreshCaptcha('login'),
                                                      icon: const Icon(Icons.refresh),
                                                      tooltip: t.refresh,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                // در تب ورود، فقط Snackbar نمایش داده می‌شود (بدون ویجت خطا)
                                                const SizedBox(height: 12),
                                                FilledButton(
                                                  onPressed: _loadingLogin ? null : _onSubmit,
                                                  child: _loadingLogin
                                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                      : Text(t.login),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_loadingLogin)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black26,
                                              alignment: Alignment.center,
                                              child: const CircularProgressIndicator(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                } else if (idx == 1) {
                                  body = Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Stack(
                                      children: [
                                        AbsorbPointer(
                                          absorbing: _loadingRegister,
                                          child: Form(
                                            key: _registerKey,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                TextFormField(
                                                  controller: _firstNameCtrl,
                                                  decoration: InputDecoration(labelText: t.firstName),
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.firstName} ${t.requiredField}' : null,
                                                  textInputAction: TextInputAction.next,
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _lastNameCtrl,
                                                  decoration: InputDecoration(labelText: t.lastName),
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.lastName} ${t.requiredField}' : null,
                                                  textInputAction: TextInputAction.next,
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _emailCtrl,
                                                  decoration: InputDecoration(labelText: t.email),
                                                  keyboardType: TextInputType.emailAddress,
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.email} ${t.requiredField}' : null,
                                                  textInputAction: TextInputAction.next,
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _mobileCtrl,
                                                  decoration: InputDecoration(labelText: t.mobile),
                                                  keyboardType: TextInputType.phone,
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.mobile} ${t.requiredField}' : null,
                                                  textInputAction: TextInputAction.next,
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _registerPasswordCtrl,
                                                  decoration: InputDecoration(labelText: t.password),
                                                  obscureText: true,
                                                  validator: (v) => (v == null || v.isEmpty) ? '${t.password} ${t.requiredField}' : null,
                                                  onFieldSubmitted: (_) => _onRegister(),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: _registerCaptchaCtrl,
                                                        decoration: InputDecoration(labelText: t.captcha),
                                                        validator: (v) => (v == null || v.trim().isEmpty) ? '${t.captcha} ${t.requiredField}' : null,
                                                        keyboardType: TextInputType.number,
                                                        inputFormatters: [
                                                          const EnglishDigitsFormatter(),
                                                          FilteringTextInputFormatter.digitsOnly,
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    if (_registerCaptchaImage != null)
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Image.memory(
                                                          _registerCaptchaImage!,
                                                          height: 40,
                                                          width: 120,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      )
                                                    else
                                                      const SizedBox(height: 40, width: 120),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: _loadingRegister ? null : () => _refreshCaptcha('register'),
                                                      icon: const Icon(Icons.refresh),
                                                      tooltip: t.refresh,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                FilledButton(
                                                  onPressed: _loadingRegister ? null : _onRegister,
                                                  child: _loadingRegister
                                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                      : Text(t.register),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_loadingRegister)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black26,
                                              alignment: Alignment.center,
                                              child: const CircularProgressIndicator(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                } else if (idx == 2) {
                                  body = Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Stack(
                                      children: [
                                        AbsorbPointer(
                                          absorbing: _loadingForgot,
                                          child: Form(
                                            key: _forgotKey,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                TextFormField(
                                                  controller: _forgotIdentifierCtrl,
                                                  decoration: InputDecoration(labelText: t.identifier),
                                                  validator: (v) => (v == null || v.trim().isEmpty) ? '${t.identifier} ${t.requiredField}' : null,
                                                  onFieldSubmitted: (_) => _onForgot(),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: _forgotCaptchaCtrl,
                                                        decoration: InputDecoration(labelText: t.captcha),
                                                        validator: (v) => (v == null || v.trim().isEmpty) ? '${t.captcha} ${t.requiredField}' : null,
                                                        keyboardType: TextInputType.number,
                                                        inputFormatters: [
                                                          const EnglishDigitsFormatter(),
                                                          FilteringTextInputFormatter.digitsOnly,
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    if (_forgotCaptchaImage != null)
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Image.memory(
                                                          _forgotCaptchaImage!,
                                                          height: 40,
                                                          width: 120,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      )
                                                    else
                                                      const SizedBox(height: 40, width: 120),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: _loadingForgot ? null : () => _refreshCaptcha('forgot'),
                                                      icon: const Icon(Icons.refresh),
                                                      tooltip: t.refresh,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                FilledButton(
                                                  onPressed: _loadingForgot ? null : _onForgot,
                                                  child: _loadingForgot
                                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                      : Text(t.sendReset),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_loadingForgot)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black26,
                                              alignment: Alignment.center,
                                              child: const CircularProgressIndicator(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                } else if (idx == 3) {
                                  // OTP Login Tab
                                  body = Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Stack(
                                      children: [
                                        AbsorbPointer(
                                          absorbing: _loadingOtpLogin,
                                          child: Form(
                                            key: _otpLoginKey,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  AppLocalizations.of(context).otpLoginTitle,
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  AppLocalizations.of(context).otpLoginSubtitle,
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                TextFormField(
                                                  controller: _otpLoginIdentifierCtrl,
                                                  enabled: _otpLoginSessionId == null,
                                                  decoration: InputDecoration(
                                                    labelText: AppLocalizations.of(context).identifier,
                                                    prefixIcon: const Icon(Icons.person),
                                                    helperText: _otpLoginSessionId != null
                                                        ? AppLocalizations.of(context).otpCodeSent
                                                        : AppLocalizations.of(context).otpLoginIdentifierHint,
                                                    suffixIcon: _loadingChannels
                                                        ? const SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: Padding(
                                                              padding: EdgeInsets.all(12.0),
                                                              child: CircularProgressIndicator(strokeWidth: 2),
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                  keyboardType: TextInputType.emailAddress,
                                                  textInputAction: TextInputAction.next,
                                                  onChanged: (_) {
                                                    if (_otpLoginSessionId == null) {
                                                      _loadAvailableChannels();
                                                    }
                                                  },
                                                  validator: (v) {
                                                    if (v == null || v.trim().isEmpty) {
                                                      return AppLocalizations.of(context).otpLoginIdentifierRequired;
                                                    }
                                                    return null;
                                                  },
                                                ),
                                                if (_otpLoginSessionId == null && _availableChannels.isNotEmpty) ...[
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    AppLocalizations.of(context).otpChannelSelectionTitle,
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  ..._availableChannels.map((channel) {
                                                    final t = AppLocalizations.of(context);
                                                    final channelNames = {
                                                      'sms': t.otpChannelSms,
                                                      'email': t.otpChannelEmail,
                                                      'telegram': t.otpChannelTelegram,
                                                    };
                                                    final channelIcons = {
                                                      'sms': Icons.sms,
                                                      'email': Icons.email,
                                                      'telegram': Icons.telegram,
                                                    };
                                                    return RadioListTile<String>(
                                                      title: Text(channelNames[channel] ?? channel),
                                                      value: channel,
                                                      groupValue: _selectedChannel,
                                                      onChanged: (value) {
                                                        setState(() {
                                                          _selectedChannel = value;
                                                        });
                                                      },
                                                      secondary: Icon(channelIcons[channel] ?? Icons.send),
                                                      dense: true,
                                                    );
                                                  }                                                  ),
                                                ],
                                                if (_otpLoginSessionId == null) ...[
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: TextFormField(
                                                          controller: _otpLoginCaptchaCtrl,
                                                          enabled: !_loadingOtpLogin,
                                                          decoration: InputDecoration(
                                                            labelText: AppLocalizations.of(context).captcha,
                                                            prefixIcon: const Icon(Icons.security),
                                                          ),
                                                          keyboardType: TextInputType.text,
                                                          textInputAction: TextInputAction.done,
                                                          validator: (v) {
                                                            if (v == null || v.trim().isEmpty) {
                                                              return AppLocalizations.of(context).captchaRequired;
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      if (_otpLoginCaptchaImage != null)
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(4),
                                                          child: Image.memory(
                                                            _otpLoginCaptchaImage!,
                                                            height: 40,
                                                            width: 120,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        )
                                                      else
                                                        const SizedBox(height: 40, width: 120),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        onPressed: _loadingOtpLogin ? null : () => _refreshCaptcha('otpLogin'),
                                                        icon: const Icon(Icons.refresh),
                                                        tooltip: AppLocalizations.of(context).refresh,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  FilledButton.icon(
                                                    onPressed: (_loadingOtpLogin || _selectedChannel == null) ? null : _sendOtpLogin,
                                                    icon: _loadingOtpLogin
                                                        ? const SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(strokeWidth: 2),
                                                          )
                                                        : const Icon(Icons.send),
                                                    label: Text(AppLocalizations.of(context).otpSendCodeButton),
                                                  ),
                                                ] else ...[
                                                  if (_availableChannels.length > 1) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      AppLocalizations.of(context).otpChangeChannelTitle,
                                                      style: const TextStyle(fontSize: 12),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      children: _availableChannels.map((channel) {
                                                        final t = AppLocalizations.of(context);
                                                        final channelNames = {
                                                          'sms': t.otpChannelSms,
                                                          'email': t.otpChannelEmail,
                                                          'telegram': t.otpChannelTelegram,
                                                        };
                                                        return OutlinedButton(
                                                          onPressed: _loadingOtpLogin ? null : () async {
                                                            setState(() {
                                                              _selectedChannel = channel;
                                                            });
                                                            await _sendOtpLogin(changeChannel: true);
                                                          },
                                                          child: Text(channelNames[channel] ?? channel),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 8),
                                                  OutlinedButton.icon(
                                                    onPressed: () {
                                                      setState(() {
                                                        _otpLoginSessionId = null;
                                                        _otpLoginIdentifierCtrl.clear();
                                                        _selectedChannel = null;
                                                        _availableChannels = [];
                                                      });
                                                    },
                                                    icon: const Icon(Icons.edit),
                                                    label: Text(AppLocalizations.of(context).otpChangeIdentifier),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_loadingOtpLogin)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black26,
                                              alignment: Alignment.center,
                                              child: const CircularProgressIndicator(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                } else {
                                  body = const SizedBox.shrink();
                                }
                                return AnimatedSize(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  alignment: Alignment.topCenter,
                                  child: body,
                                );
                              });
                            }),
                            const SizedBox(height: 8),
                            Text(t.brandTagline, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            AuthFooter(
                              localeController: widget.localeController,
                              calendarController: widget.calendarController,
                              themeController: widget.themeController,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


