import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import '../../utils/number_normalizer.dart';

/// Dialog برای وارد کردن کد OTP
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
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _verifying = false;
  bool _resending = false;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _verifying = true);
    try {
      final otp = toEnglishDigits(_otpController.text.trim());
      final success = await widget.onVerify(otp);
      if (!mounted) return;
      
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        SnackBarHelper.showError(context, message: 'کد تایید اشتباه است');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
      context,
      message: 'خطا در تایید: ${ErrorExtractor.forContext(e, context)}',
    );
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
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
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
      context,
      message: 'خطا در ارسال مجدد: ${ErrorExtractor.forContext(e, context)}',
    );
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.message, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _otpController,
                enabled: !_verifying,
                decoration: InputDecoration(
                  labelText: 'کد تایید (6 رقم)',
                  hintText: '123456',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) {
                    return 'لطفاً کد تایید را وارد کنید';
                  }
                  if (value.length != 6) {
                    return 'کد تایید باید 6 رقم باشد';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleVerify(),
              ),
              const SizedBox(height: 16),
              if (widget.onResend != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'کد را دریافت نکردید؟',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: (_resendCooldown > 0 || _resending)
                          ? null
                          : _handleResend,
                      child: _resending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _resendCooldown > 0
                                  ? 'ارسال مجدد (${_resendCooldown}s)'
                                  : 'ارسال مجدد',
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _verifying ? null : _handleVerify,
                icon: _verifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('تایید'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

