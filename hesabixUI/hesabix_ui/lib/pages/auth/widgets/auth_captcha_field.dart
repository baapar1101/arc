import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'auth_text_field.dart';

/// ویجت کپچا با باکس جدا و ظاهر حرفه‌ای.
class AuthCaptchaField extends StatelessWidget {
  final TextEditingController controller;
  final Uint8List? imageBytes;
  final bool loading;
  final String captchaMode;
  final List<TextInputFormatter> inputFormatters;
  final VoidCallback onRefresh;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final void Function(String)? onFieldSubmitted;

  const AuthCaptchaField({
    super.key,
    required this.controller,
    required this.imageBytes,
    required this.loading,
    required this.captchaMode,
    required this.inputFormatters,
    required this.onRefresh,
    this.validator,
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.captcha,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AuthTextField(
                  controller: controller,
                  label: t.captcha,
                  prefixIcon: Icons.shield_outlined,
                  focusNode: focusNode,
                  keyboardType: captchaMode == 'alphanumeric'
                      ? TextInputType.text
                      : TextInputType.number,
                  inputFormatters: inputFormatters,
                  validator: validator,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: onFieldSubmitted,
                ),
              ),
              const SizedBox(width: 12),
              _CaptchaImage(
                bytes: imageBytes,
                loading: loading,
                onRefresh: onRefresh,
                refreshTooltip: t.refresh,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptchaImage extends StatelessWidget {
  final Uint8List? bytes;
  final bool loading;
  final VoidCallback onRefresh;
  final String refreshTooltip;

  const _CaptchaImage({
    required this.bytes,
    required this.loading,
    required this.onRefresh,
    required this.refreshTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 128,
            height: 48,
            color: scheme.surface,
            alignment: Alignment.center,
            child: bytes != null
                ? Image.memory(bytes!, fit: BoxFit.contain)
                : loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.image_not_supported_outlined, color: scheme.outline),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(refreshTooltip),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ],
    );
  }
}
