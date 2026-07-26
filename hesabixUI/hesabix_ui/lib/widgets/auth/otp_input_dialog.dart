import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

import '../../pages/auth/widgets/otp_pin_input.dart';

/// Dialog برای وارد کردن کد OTP — با ۶ باکس جدا.
class OtpInputDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<bool> Function(String otp) onVerify;
  final Future<void> Function()? onResend;

  const OtpInputDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onVerify,
    this.onResend,
  });

  @override
  State<OtpInputDialog> createState() => _OtpInputDialogState();
}

class _OtpInputDialogState extends State<OtpInputDialog> {
  final _pinKey = GlobalKey<OtpPinInputState>();
  bool _verifying = false;
  bool _resending = false;
  int _resendCooldown = 0;
  String _otp = '';

  void _startResendCooldown() {
    setState(() => _resendCooldown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _resendCooldown--);
        return _resendCooldown > 0;
      }
      return false;
    });
  }

  Future<void> _handleVerify() async {
    if (_otp.length != 6) {
      SnackBarHelper.showError(context, message: 'کد تایید باید ۶ رقم باشد');
      return;
    }

    setState(() => _verifying = true);
    try {
      final success = await widget.onVerify(_otp);
      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        SnackBarHelper.showError(context, message: 'کد تایید اشتباه است');
        _pinKey.currentState?.clear();
        setState(() => _otp = '');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در تایید: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _handleResend() async {
    if (widget.onResend == null) return;

    setState(() => _resending = true);
    try {
      await widget.onResend!();
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'کد جدید ارسال شد');
      _startResendCooldown();
      _pinKey.currentState?.clear();
      setState(() => _otp = '');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در ارسال مجدد: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.mark_email_unread_outlined, color: colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            OtpPinInput(
              key: _pinKey,
              enabled: !_verifying,
              onChanged: (v) => setState(() => _otp = v),
              onCompleted: (_) => _handleVerify(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _verifying ? () {} : (_otp.length != 6 ? null : _handleVerify),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  disabledBackgroundColor: colorScheme.primary,
                  disabledForegroundColor: colorScheme.onPrimary,
                ),
                child: _verifying
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        t.login,
                        style: TextStyle(color: colorScheme.onPrimary),
                      ),
              ),
            ),
            if (widget.onResend != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'کد را دریافت نکردید؟',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: (_resending || _resendCooldown > 0) ? null : _handleResend,
                    child: _resending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Text(
                            _resendCooldown > 0 ? 'ارسال مجدد (${_resendCooldown}s)' : 'ارسال مجدد',
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
