import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'auth_captcha_field.dart';
import 'auth_primary_button.dart';
import 'auth_text_field.dart';
import 'otp_channel_picker.dart';

class OtpLoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController identifierController;
  final TextEditingController captchaController;
  final FocusNode captchaFocusNode;
  final Uint8List? captchaImage;
  final String captchaMode;
  final List<TextInputFormatter> captchaFormatters;
  final List<String> allChannels;
  final Map<String, bool> channelOnServer;
  final String? selectedChannel;
  final String? sessionId;
  final List<String> availableChannels;
  final bool loading;
  final bool loadingChannelStatus;
  final VoidCallback onSendOtp;
  final VoidCallback onRefreshCaptcha;
  final VoidCallback onBackToSignIn;
  final ValueChanged<String> onChannelSelected;
  final VoidCallback onChangeIdentifier;
  final Future<void> Function(String channel)? onChangeChannel;

  const OtpLoginForm({
    super.key,
    required this.formKey,
    required this.identifierController,
    required this.captchaController,
    required this.captchaFocusNode,
    required this.captchaImage,
    required this.captchaMode,
    required this.captchaFormatters,
    required this.allChannels,
    required this.channelOnServer,
    required this.selectedChannel,
    required this.sessionId,
    required this.availableChannels,
    required this.loading,
    required this.loadingChannelStatus,
    required this.onSendOtp,
    required this.onRefreshCaptcha,
    required this.onBackToSignIn,
    required this.onChannelSelected,
    required this.onChangeIdentifier,
    this.onChangeChannel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sent = sessionId != null;

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
                  t.otpLoginTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.otpLoginSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (loadingChannelStatus) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          AuthTextField(
            controller: identifierController,
            enabled: !sent,
            label: t.identifier,
            prefixIcon: Icons.person_outline_rounded,
            helperText: sent ? t.otpCodeSent : t.otpLoginIdentifierHint,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return t.otpLoginIdentifierRequired;
              return null;
            },
            onFieldSubmitted: (_) {
              if (!sent) captchaFocusNode.requestFocus();
            },
          ),
          if (!sent) ...[
            const SizedBox(height: 20),
            OtpChannelPicker(
              channels: allChannels,
              channelOnServer: channelOnServer,
              selected: selectedChannel,
              loading: loadingChannelStatus,
              onSelected: onChannelSelected,
            ),
            const SizedBox(height: 20),
            AuthCaptchaField(
              controller: captchaController,
              imageBytes: captchaImage,
              loading: captchaImage == null,
              captchaMode: captchaMode,
              inputFormatters: captchaFormatters,
              focusNode: captchaFocusNode,
              onRefresh: onRefreshCaptcha,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return t.captchaRequired;
                return null;
              },
              onFieldSubmitted: (_) {
                if (!loading && selectedChannel != null) onSendOtp();
              },
            ),
            const SizedBox(height: 24),
            AuthPrimaryButton(
              label: t.otpSendCodeButton,
              icon: Icons.send_rounded,
              loading: loading,
              onPressed: (loading || selectedChannel == null || channelOnServer[selectedChannel!] != true)
                  ? null
                  : onSendOtp,
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.otpCodeSent,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (availableChannels.length > 1) ...[
              const SizedBox(height: 16),
              Text(t.otpChangeChannelTitle, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableChannels.map((channel) {
                  final names = {
                    'sms': t.otpChannelSms,
                    'email': t.otpChannelEmail,
                    'telegram': t.otpChannelTelegram,
                    'bale': 'بله',
                  };
                  return OutlinedButton(
                    onPressed: loading || onChangeChannel == null
                        ? null
                        : () => onChangeChannel!(channel),
                    child: Text(names[channel] ?? channel),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: loading ? null : onChangeIdentifier,
              icon: const Icon(Icons.edit_outlined),
              label: Text(t.otpChangeIdentifier),
            ),
          ],
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
