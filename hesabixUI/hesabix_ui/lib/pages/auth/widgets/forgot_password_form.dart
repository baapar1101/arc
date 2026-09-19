import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'auth_captcha_field.dart';
import 'auth_primary_button.dart';
import 'auth_text_field.dart';

class ForgotPasswordForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController identifierController;
  final TextEditingController captchaController;
  final Uint8List? captchaImage;
  final String captchaMode;
  final List<TextInputFormatter> captchaFormatters;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onRefreshCaptcha;
  final VoidCallback onBackToSignIn;

  const ForgotPasswordForm({
    super.key,
    required this.formKey,
    required this.identifierController,
    required this.captchaController,
    required this.captchaImage,
    required this.captchaMode,
    required this.captchaFormatters,
    required this.loading,
    required this.onSubmit,
    required this.onRefreshCaptcha,
    required this.onBackToSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: loading ? null : onBackToSignIn,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: t.authBackToSignIn,
              ),
              Expanded(
                child: Text(
                  t.authForgotTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.authForgotSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          AuthTextField(
            controller: identifierController,
            label: t.identifier,
            prefixIcon: Icons.person_outline_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '${t.identifier} ${t.requiredField}' : null,
          ),
          const SizedBox(height: 20),
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
            label: t.sendReset,
            loading: loading,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: loading ? null : onBackToSignIn,
            child: Text(t.authBackToSignIn),
          ),
        ],
      ),
    );
  }
}
