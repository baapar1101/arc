import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/api_client.dart';
import '../core/calendar_controller.dart';
import '../core/auth_store.dart';
import '../core/locale_controller.dart';
import '../core/mobile_launcher_prefs.dart';
import '../core/referral_store.dart';
import '../theme/theme_controller.dart';
import '../utils/number_normalizer.dart';
import '../utils/password_validator.dart';
import '../services/otp_login_service.dart';
import '../services/password_reset_otp_service.dart';
import '../services/errors/api_error.dart';
import '../utils/error_extractor.dart';
import '../widgets/auth/otp_input_dialog.dart';
import '../../utils/snackbar_helper.dart';
import 'auth/auth_flow.dart';
import 'auth/widgets/auth_shell.dart';
import 'auth/widgets/forgot_password_form.dart';
import 'auth/widgets/otp_login_form.dart';
import 'auth/widgets/sign_in_form.dart';
import 'auth/widgets/sign_up_wizard.dart';


class LoginPage extends StatefulWidget {
  final LocaleController localeController;
  final CalendarController calendarController;
  final ThemeController? themeController;
  final AuthStore authStore;
  const LoginPage({super.key, required this.localeController, required this.calendarController, this.themeController, required this.authStore});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
  final _signUpWizardKey = GlobalKey<SignUpWizardState>();
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
  // Terms acceptance
  bool _acceptedTerms = false;
  final TapGestureRecognizer _privacyTapRecognizer = TapGestureRecognizer();
  final TapGestureRecognizer _termsTapRecognizer = TapGestureRecognizer();

  // Forgot password
  final _forgotKey = GlobalKey<FormState>();
  final _forgotIdentifierCtrl = TextEditingController();
  final _forgotCaptchaCtrl = TextEditingController();
  String? _forgotCaptchaId;
  Uint8List? _forgotCaptchaImage;
  bool _loadingForgot = false;
  Timer? _forgotCaptchaTimer;

  /// دیپ‌لینک: /login?reset_token=...
  bool _resetDeepLinkScheduled = false;

  // OTP Login
  final _otpLoginKey = GlobalKey<FormState>();
  final _otpLoginIdentifierCtrl = TextEditingController();
  final _otpLoginCaptchaCtrl = TextEditingController();
  String? _otpLoginCaptchaId;
  Uint8List? _otpLoginCaptchaImage;
  Timer? _otpLoginCaptchaTimer;
  final FocusNode _otpLoginCaptchaFocus = FocusNode();
  String? _otpLoginSessionId;
  String? _selectedChannel;
  List<String> _availableChannels = [];
  bool _loadingOtpLogin = false;
  static const List<String> _otpAllChannels = ['sms', 'email', 'telegram', 'bale'];
  /// پیکربندی کانال روی سرور (true = سرویس فعال است)
  final Map<String, bool> _otpChannelOnServer = {};
  bool _loadingOtpChannelStatus = true;
  /// از پاسخ `/auth/captcha` — همه کپچاهای صفحه از یک تنظیم سرور تبعیت می‌کنند.
  String _captchaMode = 'numeric';

  AuthFlow _flow = AuthFlow.signIn;
  bool _registrationEnabled = true;

  List<TextInputFormatter> get _captchaInputFormatters => _captchaMode == 'alphanumeric'
      ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))]
      : <TextInputFormatter>[const EnglishDigitsFormatter(), FilteringTextInputFormatter.digitsOnly];

  String _normalizeCaptchaCode(String raw) {
    final s = raw.trim();
    if (_captchaMode == 'alphanumeric') {
      return s.toUpperCase();
    }
    return toEnglishDigits(s);
  }

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
    _otpLoginCaptchaFocus.dispose();
    _privacyTapRecognizer.dispose();
    _termsTapRecognizer.dispose();
    super.dispose();
  }

  void _goToFlow(AuthFlow flow) {
    if (_flow == flow) return;
    setState(() => _flow = flow);
  }

  Future<void> _refreshCaptcha(String scope, {bool clearOtpChannels = true}) async {
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
      final m = data['captcha_mode']?.toString();
      setState(() {
        if (m == 'alphanumeric' || m == 'numeric') {
          _captchaMode = m!;
        }
        if (scope == 'login') _loginCaptchaId = id;
        if (scope == 'register') _registerCaptchaId = id;
        if (scope == 'forgot') _forgotCaptchaId = id;
        if (scope == 'otpLogin') {
          _otpLoginCaptchaId = id;
          _otpLoginCaptchaCtrl.clear();
          if (clearOtpChannels) {
            _availableChannels = [];
            _selectedChannel = null;
          }
        }
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
          _otpLoginCaptchaTimer = Timer(delay, () => _refreshCaptcha('otpLogin', clearOtpChannels: true));
        }
      }
    } catch (_) {
      // سکوت: خطای شبکه/شکل پاسخ نباید باعث کرش شود
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshCaptcha('login');
    _refreshCaptcha('register');
    _refreshCaptcha('forgot');
    _refreshCaptcha('otpLogin');
    unawaited(_loadOtpChannelStatus());
    unawaited(ReferralStore.captureFromCurrentUrl());
    unawaited(_loadPublicAuthSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) => _readFlowFromUrl());
  }

  void _readFlowFromUrl() {
    if (!mounted) return;
    try {
      final view = GoRouterState.of(context).uri.queryParameters['view'];
      switch (view) {
        case 'signup':
        case 'register':
          if (_registrationEnabled) _goToFlow(AuthFlow.signUp);
        case 'forgot':
          _goToFlow(AuthFlow.forgotPassword);
        case 'otp':
          _goToFlow(AuthFlow.otpLogin);
      }
    } catch (_) {}
  }

  void _applyRegistrationEnabledFromServer(bool enabled) {
    if (_registrationEnabled == enabled) return;
    setState(() {
      _registrationEnabled = enabled;
      if (!enabled && _flow == AuthFlow.signUp) {
        _flow = AuthFlow.signIn;
      }
    });
  }

  Future<void> _loadPublicAuthSettings() async {
    try {
      final api = ApiClient();
      final res = await api.get<Map<String, dynamic>>('/api/v1/auth/public-config');
      final body = res.data;
      var enabled = true;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic> && data['enable_registration'] is bool) {
          enabled = data['enable_registration'] as bool;
        }
      }
      if (!mounted) return;
      _applyRegistrationEnabledFromServer(enabled);
    } catch (_) {
      // در خطای شبکه همان پیش‌فرض (ثبت‌نام فعال) حفظ می‌شود
    }
  }

  Future<void> _loadOtpChannelStatus() async {
    setState(() {
      _loadingOtpChannelStatus = true;
    });
    try {
      final data = await OtpLoginService(ApiClient()).getOtpChannelStatus();
      if (!mounted) return;
      setState(() {
        for (final c in _otpAllChannels) {
          _otpChannelOnServer[c] = data[c] == true;
        }
        _ensureOtpChannelSelection();
        _loadingOtpChannelStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final c in _otpAllChannels) {
          _otpChannelOnServer[c] = true;
        }
        _ensureOtpChannelSelection();
        _loadingOtpChannelStatus = false;
      });
    }
  }

  void _ensureOtpChannelSelection() {
    String? firstOk;
    for (final c in _otpAllChannels) {
      if (_otpChannelOnServer[c] == true) {
        firstOk = c;
        break;
      }
    }
    if (firstOk != null &&
        (_selectedChannel == null || _otpChannelOnServer[_selectedChannel!] != true)) {
      _selectedChannel = firstOk;
    } else if (_selectedChannel == null) {
      _selectedChannel = _otpAllChannels.first;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resetDeepLinkScheduled) return;
    String? t;
    try {
      t = GoRouterState.of(context).uri.queryParameters['reset_token'] ??
          GoRouterState.of(context).uri.queryParameters['token'];
    } catch (_) {
      t = null;
    }
    if (t == null || t.isEmpty) return;
    _resetDeepLinkScheduled = true;
    final tok = t;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showResetPasswordDialog(context, tok));
    });
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
    return ErrorExtractor.extractErrorMessage(e, t);
  }

  int? _registerFieldToStep(String? field) {
    switch (field) {
      case 'email':
      case 'mobile':
        return 0;
      case 'first_name':
      case 'last_name':
      case 'password':
        return 1;
      case 'captcha':
      case 'captcha_code':
        return 2;
      default:
        return null;
    }
  }

  int? _inferRegisterErrorStep(Object e) {
    try {
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          final err = data['error'] is Map ? data['error'] as Map : null;
          final code = (err?['code'] ?? data['error_code'])?.toString();
          switch (code) {
            case 'EMAIL_IN_USE':
            case 'MOBILE_IN_USE':
            case 'INVALID_MOBILE':
            case 'IDENTIFIER_REQUIRED':
              return 0;
            case 'INVALID_CAPTCHA':
              return 2;
          }

          List<dynamic>? details;
          if (err != null && err['details'] is List) {
            details = err['details'] as List;
          } else if (data['detail'] is List) {
            details = data['detail'] as List;
          }
          if (details != null) {
            for (final item in details) {
              if (item is Map) {
                final fieldRaw = (item['field'] ??
                        (item['loc'] is List
                            ? (item['loc'] as List).isNotEmpty
                                ? (item['loc'] as List).last?.toString()
                                : null
                            : null))
                    ?.toString();
                final step = _registerFieldToStep(fieldRaw);
                if (step != null) return step;
              }
            }
          }

          final message = (err?['message'] ?? data['message'])?.toString().toLowerCase() ?? '';
          if (message.contains('email') ||
              message.contains('mobile') ||
              message.contains('ایمیل') ||
              message.contains('موبایل') ||
              message.contains('شماره')) {
            return 0;
          }
          if (message.contains('captcha') || message.contains('کپچا') || message.contains('امنیتی')) {
            return 2;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }

  Future<void> _sendOtpLogin({bool changeChannel = false}) async {
    final form = _otpLoginKey.currentState;
    if (form == null || !form.validate()) return;
    
    if (_selectedChannel == null || _selectedChannel!.isEmpty) {
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).otpSelectChannelError);
      return;
    }

    if (_otpChannelOnServer[_selectedChannel!] != true) {
      SnackBarHelper.showError(
        context,
        message: 'این روش دریافت کد روی سرور فعال نیست؛ روش دیگری را انتخاب کنید.',
      );
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
        captchaCode: _normalizeCaptchaCode(_otpLoginCaptchaCtrl.text),
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
          'bale': 'بله',
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

                  final home = await MobileLauncherPrefs.postAuthHomeLocation(widget.authStore.currentUserId);
                  if (!mounted) return true;
                  context.go(home);
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
                  errorMessage =
                      'خطا در ورود: ${ErrorExtractor.extractErrorMessage(e, AppLocalizations.of(context))}';
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
                  captchaCode: _normalizeCaptchaCode(captchaCode),
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
                  errorMessage =
                      'خطا در ارسال مجدد کد: ${ErrorExtractor.extractErrorMessage(e, AppLocalizations.of(context))}';
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
        errorMessage =
            'خطا در ارسال کد: ${ErrorExtractor.extractErrorMessage(e, t)}';
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
          'captcha_code': _normalizeCaptchaCode(_loginCaptchaCtrl.text),
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
          final home = await MobileLauncherPrefs.postAuthHomeLocation(widget.authStore.currentUserId);
          if (!mounted) return;
          context.go(home);
        }
      } catch (e) {
        // اگر GoRouterState در دسترس نیست، به dashboard برود
        final home = await MobileLauncherPrefs.postAuthHomeLocation(widget.authStore.currentUserId);
        if (!mounted) return;
        context.go(home);
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
    if (!_acceptedTerms) {
      _showSnack(t.acceptTermsRequired);
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
          'captcha_code': _normalizeCaptchaCode(_registerCaptchaCtrl.text),
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
        final home = await MobileLauncherPrefs.postAuthHomeLocation(widget.authStore.currentUserId);
        if (!mounted) return;
        context.go(home);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _extractErrorMessage(e, AppLocalizations.of(context));
      _showSnack(msg.isEmpty ? t.registerFailed : msg);
      final errorStep = _inferRegisterErrorStep(e);
      if (errorStep != null) {
        _signUpWizardKey.currentState?.goToStep(errorStep);
      }
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
          captchaCode: _normalizeCaptchaCode(_forgotCaptchaCtrl.text),
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
                SnackBarHelper.showError(
                  ctx,
                  message: 'خطا در تایید: ${ErrorExtractor.extractErrorMessage(e, AppLocalizations.of(ctx))}',
                );
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
            'captcha_code': _normalizeCaptchaCode(_forgotCaptchaCtrl.text),
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
    var dialogCaptchaMode = _captchaMode;

    // تابع برای دریافت کپچا
    Future<void> loadCaptcha() async {
      try {
        final api = ApiClient();
        final captchaRes = await api.post<Map<String, dynamic>>('/api/v1/auth/captcha');
        final captchaData = captchaRes.data?['data'] as Map<String, dynamic>?;
        final String? id = captchaData?['captcha_id']?.toString();
        final String? imgB64 = captchaData?['image_base64']?.toString();
        final int? ttl = (captchaData?['ttl_seconds'] as num?)?.toInt();
        final m = captchaData?['captcha_mode']?.toString();
        if (m == 'alphanumeric' || m == 'numeric') {
          dialogCaptchaMode = m!;
        }
        
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
                      if (passwordExceedsMaxBytes(v)) {
                        return AppLocalizations.of(dialogContext).passwordMaxLength;
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
                          keyboardType: dialogCaptchaMode == 'alphanumeric' ? TextInputType.text : TextInputType.number,
                          inputFormatters: dialogCaptchaMode == 'alphanumeric'
                              ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))]
                              : <TextInputFormatter>[const EnglishDigitsFormatter(), FilteringTextInputFormatter.digitsOnly],
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
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.primary,
                foregroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
                disabledBackgroundColor: Theme.of(dialogContext).colorScheme.primary,
                disabledForegroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
              ),
              onPressed: saving ? () {} : () async {
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
                      'captcha_code': dialogCaptchaMode == 'alphanumeric'
                          ? captchaCtrl.text.trim().toUpperCase()
                          : toEnglishDigits(captchaCtrl.text.trim()),
                    },
                  );
                  
                  if (dialogContext.mounted) {
                    captchaTimer?.cancel();
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    final tDialog = AppLocalizations.of(dialogContext);
                    final msg = _extractErrorMessage(e, tDialog);
                    SnackBarHelper.showError(
                      dialogContext,
                      message: msg.isNotEmpty
                          ? msg
                          : 'خطا در تغییر رمز عبور: ${ErrorExtractor.extractErrorMessage(e, tDialog)}',
                    );
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
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(dialogContext).colorScheme.onPrimary,
                      ),
                    )
                  : Text(
                      'تغییر رمز عبور',
                      style: TextStyle(color: Theme.of(dialogContext).colorScheme.onPrimary),
                    ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoAsset = isDark ? 'assets/images/logo-light.png' : 'assets/images/logo-blue.png';

    return AuthShell(
      logoAsset: logoAsset,
      localeController: widget.localeController,
      calendarController: widget.calendarController,
      themeController: widget.themeController,
      formPanel: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_flow),
          child: _buildFlowContent(),
        ),
      ),
    );
  }

  Widget _buildFlowContent() {
    switch (_flow) {
      case AuthFlow.signIn:
        return SignInForm(
          formKey: _formKey,
          identifierController: _identifierCtrl,
          passwordController: _passwordCtrl,
          captchaController: _loginCaptchaCtrl,
          captchaImage: _loginCaptchaImage,
          captchaMode: _captchaMode,
          captchaFormatters: _captchaInputFormatters,
          loading: _loadingLogin,
          registrationEnabled: _registrationEnabled,
          onSubmit: _onSubmit,
          onRefreshCaptcha: () => _refreshCaptcha('login'),
          onForgotPassword: () => _goToFlow(AuthFlow.forgotPassword),
          onOtpLogin: () => _goToFlow(AuthFlow.otpLogin),
          onSignUp: _registrationEnabled ? () => _goToFlow(AuthFlow.signUp) : null,
        );
      case AuthFlow.signUp:
        return SignUpWizard(
          key: _signUpWizardKey,
          formKey: _registerKey,
          firstNameController: _firstNameCtrl,
          lastNameController: _lastNameCtrl,
          emailController: _emailCtrl,
          mobileController: _mobileCtrl,
          passwordController: _registerPasswordCtrl,
          captchaController: _registerCaptchaCtrl,
          captchaImage: _registerCaptchaImage,
          captchaMode: _captchaMode,
          captchaFormatters: _captchaInputFormatters,
          loading: _loadingRegister,
          acceptedTerms: _acceptedTerms,
          onAcceptedTermsChanged: (v) => setState(() => _acceptedTerms = v),
          privacyRecognizer: _privacyTapRecognizer,
          termsRecognizer: _termsTapRecognizer,
          onSubmit: _onRegister,
          onRefreshCaptcha: () => _refreshCaptcha('register'),
          onBackToSignIn: () => _goToFlow(AuthFlow.signIn),
        );
      case AuthFlow.forgotPassword:
        return ForgotPasswordForm(
          formKey: _forgotKey,
          identifierController: _forgotIdentifierCtrl,
          captchaController: _forgotCaptchaCtrl,
          captchaImage: _forgotCaptchaImage,
          captchaMode: _captchaMode,
          captchaFormatters: _captchaInputFormatters,
          loading: _loadingForgot,
          onSubmit: _onForgot,
          onRefreshCaptcha: () => _refreshCaptcha('forgot'),
          onBackToSignIn: () => _goToFlow(AuthFlow.signIn),
        );
      case AuthFlow.otpLogin:
        return OtpLoginForm(
          formKey: _otpLoginKey,
          identifierController: _otpLoginIdentifierCtrl,
          captchaController: _otpLoginCaptchaCtrl,
          captchaFocusNode: _otpLoginCaptchaFocus,
          captchaImage: _otpLoginCaptchaImage,
          captchaMode: _captchaMode,
          captchaFormatters: _captchaInputFormatters,
          allChannels: _otpAllChannels,
          channelOnServer: _otpChannelOnServer,
          selectedChannel: _selectedChannel,
          sessionId: _otpLoginSessionId,
          availableChannels: _availableChannels,
          loading: _loadingOtpLogin,
          loadingChannelStatus: _loadingOtpChannelStatus,
          onSendOtp: _sendOtpLogin,
          onRefreshCaptcha: () => _refreshCaptcha('otpLogin'),
          onBackToSignIn: () => _goToFlow(AuthFlow.signIn),
          onChannelSelected: (ch) => setState(() => _selectedChannel = ch),
          onChangeIdentifier: () {
            setState(() {
              _otpLoginSessionId = null;
              _otpLoginIdentifierCtrl.clear();
              _availableChannels = [];
              _ensureOtpChannelSelection();
            });
          },
          onChangeChannel: (channel) async {
            setState(() => _selectedChannel = channel);
            await _sendOtpLogin(changeChannel: true);
          },
        );
    }
  }
}
