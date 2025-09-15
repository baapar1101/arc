import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../widgets/language_switcher.dart';
import '../widgets/theme_mode_switcher.dart';
import '../theme/theme_controller.dart';
import '../widgets/auth_footer.dart';

class LoginPage extends StatefulWidget {
  final LocaleController localeController;
  final ThemeController? themeController;
  const LoginPage({super.key, required this.localeController, this.themeController});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  // Login
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loadingLogin = false;
  String? _errorText;

  // Register
  final _registerKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _registerPasswordCtrl = TextEditingController();
  bool _loadingRegister = false;

  // Forgot password
  final _forgotKey = GlobalKey<FormState>();
  final _forgotEmailCtrl = TextEditingController();
  bool _loadingForgot = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _registerPasswordCtrl.dispose();
    _forgotEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _loadingLogin = true;
      _errorText = null;
    });

    try {
      final api = ApiClient();
      await api.post<Map<String, dynamic>>(
        '/user/login',
        data: {
          'username': _usernameCtrl.text.trim(),
          'password': _passwordCtrl.text,
        },
      );

      if (!mounted) return;
      // روی موفقیت ساده به / هدایت می‌کنیم. در آینده توکن/پروفایل ذخیره می‌شود.
      context.go('/');
    } catch (e) {
      setState(() {
        _errorText = 'ورود ناموفق بود. لطفاً دوباره تلاش کنید.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingLogin = false;
        });
      }
    }
  }

  Future<void> _onRegister() async {
    final form = _registerKey.currentState;
    final t = AppLocalizations.of(context);
    if (form == null || !form.validate()) return;

    setState(() => _loadingRegister = true);
    try {
      final api = ApiClient();
      await api.post<Map<String, dynamic>>(
        '/user/register',
        data: {
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'mobile': _mobileCtrl.text.trim(),
          'password': _registerPasswordCtrl.text,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.registerSuccess)));
      DefaultTabController.of(context)?.animateTo(0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.loginFailed)));
    } finally {
      if (mounted) setState(() => _loadingRegister = false);
    }
  }

  Future<void> _onForgot() async {
    final form = _forgotKey.currentState;
    final t = AppLocalizations.of(context);
    if (form == null || !form.validate()) return;

    setState(() => _loadingForgot = true);
    try {
      final api = ApiClient();
      await api.post<Map<String, dynamic>>(
        '/user/forgot-password',
        data: {
          'email': _forgotEmailCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.forgotSent)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.loginFailed)));
    } finally {
      if (mounted) setState(() => _loadingForgot = false);
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
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _usernameCtrl,
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
                                  const SizedBox(height: 16),
                                  if (_errorText != null)
                                    Text(_errorText!, style: const TextStyle(color: Colors.red)),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _loadingLogin ? null : _onSubmit,
                                    child: _loadingLogin
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(t.submit),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if (idx == 1) {
                          body = Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: _loadingRegister ? null : _onRegister,
                                    child: _loadingRegister
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(t.submit),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          body = Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Form(
                              key: _forgotKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _forgotEmailCtrl,
                                    decoration: InputDecoration(labelText: t.email),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) => (v == null || v.trim().isEmpty) ? '${t.email} ${t.requiredField}' : null,
                                    onFieldSubmitted: (_) => _onForgot(),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _loadingForgot ? null : _onForgot,
                                    child: _loadingForgot
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(t.submit),
                                  ),
                                ],
                              ),
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
                    AuthFooter(localeController: widget.localeController, themeController: widget.themeController),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


