import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../utils/password_validator.dart';
import 'auth_captcha_field.dart';
import 'auth_or_divider.dart';
import 'auth_password_field.dart';
import 'auth_primary_button.dart';
import 'auth_text_field.dart';

class SignInForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController identifierController;
  final TextEditingController passwordController;
  final TextEditingController captchaController;
  final Uint8List? captchaImage;
  final String captchaMode;
  final List<TextInputFormatter> captchaFormatters;
  final bool loading;
  final bool registrationEnabled;
  final VoidCallback onSubmit;
  final VoidCallback onRefreshCaptcha;
  final VoidCallback onForgotPassword;
  final VoidCallback onOtpLogin;
  final VoidCallback? onSignUp;

  const SignInForm({
    super.key,
    required this.formKey,
    required this.identifierController,
    required this.passwordController,
    required this.captchaController,
    required this.captchaImage,
    required this.captchaMode,
    required this.captchaFormatters,
    required this.loading,
    required this.registrationEnabled,
    required this.onSubmit,
    required this.onRefreshCaptcha,
    required this.onForgotPassword,
    required this.onOtpLogin,
    this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.authSignInTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            t.authSignInSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          AuthTextField(
            controller: identifierController,
            label: t.identifier,
            prefixIcon: Icons.person_outline_rounded,
            autofillHint: AutofillHints.username,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '${t.identifier} ${t.requiredField}' : null,
          ),
          const SizedBox(height: 16),
          AuthPasswordField(
            controller: passwordController,
            label: t.password,
            validator: (v) {
              if (v == null || v.isEmpty) return '${t.password} ${t.requiredField}';
              if (passwordExceedsMaxBytes(v)) return t.passwordMaxLength;
              return null;
            },
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: loading ? null : onForgotPassword,
              child: Text(t.forgotPassword),
            ),
          ),
          const SizedBox(height: 8),
          AuthCaptchaField(
            controller: captchaController,
            imageBytes: captchaImage,
            loading: captchaImage == null,
            captchaMode: captchaMode,
            inputFormatters: captchaFormatters,
            onRefresh: onRefreshCaptcha,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '${t.captcha} ${t.requiredField}' : null,
            onFieldSubmitted: (_) {
              if (!loading) onSubmit();
            },
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: t.login,
            loading: loading,
            onPressed: onSubmit,
          ),
          const AuthOrDivider(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onOtpLogin,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.sms_outlined),
              label: Text(t.otpLogin),
            ),
          ),
          if (registrationEnabled && onSignUp != null) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.authNoAccount,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: loading ? null : onSignUp,
                  child: Text(t.register),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
