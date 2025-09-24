import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../theme/theme_controller.dart';
import '../widgets/auth_footer.dart';
import '../core/auth_store.dart';
import '../core/referral_store.dart';

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
        if (scope == 'login') _loginCaptchaImage = bytes;
        if (scope == 'register') _registerCaptchaImage = bytes;
        if (scope == 'forgot') _forgotCaptchaImage = bytes;
      });
      if (ttl != null && ttl > 0) {
        final delay = Duration(seconds: ttl);
        if (scope == 'login') {
          _loginCaptchaTimer?.cancel();
          _loginCaptchaTimer = Timer(delay, () => _refreshCaptcha('login'));
        } else if (scope == 'register') {
          _registerCaptchaTimer?.cancel();
          _registerCaptchaTimer = Timer(delay, () => _refreshCaptcha('register'));
        } else if (scope == 'forgot') {
          _forgotCaptchaTimer?.cancel();
          _forgotCaptchaTimer = Timer(delay, () => _refreshCaptcha('forgot'));
        }
      }
    } catch (_) {
      // سکوت: خطای شبکه/شکل پاسخ نباید باعث کرش شود
    }
  }

  @override
  void initState() {
    super.initState();
    // پیش‌بارگذاری کپچا برای هر سه تب
    _refreshCaptcha('login');
    _refreshCaptcha('register');
    _refreshCaptcha('forgot');
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onSubmit() async {
    final form = _formKey.currentState;
    final t = AppLocalizations.of(context);
    if (form == null || !form.validate()) return;
    if ((_loginCaptchaCtrl.text.trim().isEmpty) || (_loginCaptchaId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.captchaRequired)));
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
      
      // ذخیره دسترسی‌های اپلیکیشن
      final appPermissions = user?['app_permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = appPermissions?['superadmin'] == true;
      final userId = user?['id'] as int?;
      
      if (appPermissions != null) {
        await widget.authStore.saveAppPermissions(appPermissions, isSuperAdmin, userId: userId);
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
      
      // ذخیره دسترسی‌های اپلیکیشن
      final appPermissions = user?['app_permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = appPermissions?['superadmin'] == true;
      final userId = user?['id'] as int?;
      
      if (appPermissions != null) {
        await widget.authStore.saveAppPermissions(appPermissions, isSuperAdmin, userId: userId);
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
      final api = ApiClient();
      await api.post<Map<String, dynamic>>(
        '/api/v1/auth/forgot-password',
        data: {
          'identifier': _forgotIdentifierCtrl.text.trim(),
          'captcha_id': _forgotCaptchaId,
          'captcha_code': _forgotCaptchaCtrl.text.trim(),
          'referrer_code': await ReferralStore.getReferrerCode(),
        },
      );

      if (!mounted) return;
      _showSnack(t.forgotSent);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String logoAsset = isDark
        ? 'assets/images/logo-light.png'
        : 'assets/images/logo-blue.png';
    return DefaultTabController(
      length: 3,
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
                      maxWidth: 520,
                      minHeight: constraints.maxHeight - 32, // to keep card vertically centered when possible
                    ),
                    child: Card(
                      elevation: 2,
                      margin: const EdgeInsets.all(16),
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
                            TabBar(tabs: [Tab(text: t.login), Tab(text: t.register), Tab(text: t.forgotPassword)]),
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
                                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                                } else {
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
                                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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


