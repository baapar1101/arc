import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../utils/password_validator.dart';
import 'auth_captcha_field.dart';
import 'auth_password_field.dart';
import 'auth_primary_button.dart';
import 'auth_text_field.dart';
import 'password_strength_meter.dart';

class SignUpWizard extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController mobileController;
  final TextEditingController passwordController;
  final TextEditingController captchaController;
  final Uint8List? captchaImage;
  final String captchaMode;
  final List<TextInputFormatter> captchaFormatters;
  final bool loading;
  final bool acceptedTerms;
  final ValueChanged<bool> onAcceptedTermsChanged;
  final TapGestureRecognizer privacyRecognizer;
  final TapGestureRecognizer termsRecognizer;
  final VoidCallback onSubmit;
  final VoidCallback onRefreshCaptcha;
  final VoidCallback onBackToSignIn;

  const SignUpWizard({
    super.key,
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.mobileController,
    required this.passwordController,
    required this.captchaController,
    required this.captchaImage,
    required this.captchaMode,
    required this.captchaFormatters,
    required this.loading,
    required this.acceptedTerms,
    required this.onAcceptedTermsChanged,
    required this.privacyRecognizer,
    required this.termsRecognizer,
    required this.onSubmit,
    required this.onRefreshCaptcha,
    required this.onBackToSignIn,
  });

  @override
  State<SignUpWizard> createState() => _SignUpWizardState();
}

class _SignUpWizardState extends State<SignUpWizard> {
  int _step = 0;

  bool _validateStep0(AppLocalizations t) {
    if (widget.emailController.text.trim().isEmpty &&
        widget.mobileController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.email} / ${t.mobile} ${t.requiredField}')),
      );
      return false;
    }
    return true;
  }

  bool _validateStep1(AppLocalizations t) {
    if (widget.firstNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${t.firstName} ${t.requiredField}')));
      return false;
    }
    if (widget.lastNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${t.lastName} ${t.requiredField}')));
      return false;
    }
    final pw = widget.passwordController.text;
    if (pw.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${t.password} ${t.requiredField}')));
      return false;
    }
    final err = validatePassword(
      value: pw,
      getRequiredError: () => '${t.password} ${t.requiredField}',
      getMinLengthError: () => t.passwordMinLength,
      getMaxLengthError: () => t.passwordMaxLength,
      minLength: 8,
    );
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return false;
    }
    return true;
  }

  void _next() {
    final t = AppLocalizations.of(context);
    if (_step == 0 && !_validateStep0(t)) return;
    if (_step == 1 && !_validateStep1(t)) return;
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      widget.onBackToSignIn();
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.loading ? null : _back,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: t.authBackToSignIn,
              ),
              Expanded(
                child: Text(
                  t.authSignUpTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _StepIndicator(current: _step, labels: [t.authStepContact, t.authStepProfile, t.authStepSecurity]),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: _step == 0
                ? _buildStep0(t)
                : _step == 1
                    ? _buildStep1(t)
                    : _buildStep2(t, scheme),
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: _step < 2 ? t.authContinue : t.register,
            loading: widget.loading,
            onPressed: widget.loading
                ? null
                : () {
                    if (_step < 2) {
                      _next();
                    } else {
                      widget.onSubmit();
                    }
                  },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(t.authHaveAccount, style: Theme.of(context).textTheme.bodyMedium),
              TextButton(
                onPressed: widget.loading ? null : widget.onBackToSignIn,
                child: Text(t.login),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep0(AppLocalizations t) {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.authSignUpStepContactHint, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        AuthTextField(
          controller: widget.emailController,
          label: t.email,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          autofillHint: AutofillHints.email,
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: widget.mobileController,
          label: t.mobile,
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          autofillHint: AutofillHints.telephoneNumber,
        ),
      ],
    );
  }

  Widget _buildStep1(AppLocalizations t) {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AuthTextField(
                controller: widget.firstNameController,
                label: t.firstName,
                prefixIcon: Icons.badge_outlined,
                autofillHint: AutofillHints.givenName,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AuthTextField(
                controller: widget.lastNameController,
                label: t.lastName,
                prefixIcon: Icons.badge_outlined,
                autofillHint: AutofillHints.familyName,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AuthPasswordField(
          controller: widget.passwordController,
          label: t.password,
          onFieldSubmitted: (_) {},
        ),
        ListenableBuilder(
          listenable: widget.passwordController,
          builder: (_, __) => PasswordStrengthMeter(password: widget.passwordController.text),
        ),
      ],
    );
  }

  Widget _buildStep2(AppLocalizations t, ColorScheme scheme) {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthCaptchaField(
          controller: widget.captchaController,
          imageBytes: widget.captchaImage,
          loading: widget.captchaImage == null,
          captchaMode: widget.captchaMode,
          inputFormatters: widget.captchaFormatters,
          onRefresh: widget.onRefreshCaptcha,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: widget.acceptedTerms,
          onChanged: widget.loading ? null : (v) => widget.onAcceptedTermsChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
              children: [
                TextSpan(text: t.acceptTermsPrefix),
                TextSpan(
                  text: t.privacyPolicy,
                  style: TextStyle(color: scheme.primary),
                  recognizer: widget.privacyRecognizer
                    ..onTap = () => launchUrlString('https://hesabix.ir/page/privacy/'),
                ),
                TextSpan(text: ' ${t.and} '),
                TextSpan(
                  text: t.termsOfService,
                  style: TextStyle(color: scheme.primary),
                  recognizer: widget.termsRecognizer
                    ..onTap = () => launchUrlString('https://hesabix.ir/page/terms/'),
                ),
                TextSpan(text: t.acceptTermsSuffix),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final List<String> labels;

  const _StepIndicator({required this.current, required this.labels});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: List.generate(labels.length, (i) {
        final active = i <= current;
        final done = i < current;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? scheme.primary : scheme.surfaceContainerHighest,
                        border: Border.all(
                          color: active ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: done
                          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: active ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
              if (i < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: i < current ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
