import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/mobile_verification_service.dart';
import '../../widgets/auth/otp_input_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_normalizer.dart' show toEnglishDigits;

class MobileVerificationPage extends StatefulWidget {
  const MobileVerificationPage({super.key});

  @override
  State<MobileVerificationPage> createState() => _MobileVerificationPageState();
}

class _MobileVerificationPageState extends State<MobileVerificationPage> {
  final _service = MobileVerificationService(ApiClient());
  bool _loading = false;
  bool _otpSent = false;
  String? _mobileNumber;

  Future<void> _sendVerificationCode(String mobile) async {
    if (mobile.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً شماره موبایل را وارد کنید');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // نرمال‌سازی شماره موبایل
      final normalizedMobile = toEnglishDigits(mobile.trim());
      // تبدیل به فرمت 0912...
      String iranianMobile = normalizedMobile;
      if (iranianMobile.startsWith('+989')) {
        iranianMobile = '0${iranianMobile.substring(3)}';
      } else if (iranianMobile.startsWith('00989')) {
        iranianMobile = '0${iranianMobile.substring(4)}';
      } else if (iranianMobile.startsWith('989') && iranianMobile.length >= 12) {
        iranianMobile = '0${iranianMobile.substring(2)}';
      } else if (iranianMobile.startsWith('9') && iranianMobile.length == 10) {
        iranianMobile = '0$iranianMobile';
      }
      
      await _service.sendMobileVerification(iranianMobile);
      
      if (!mounted) return;
      
      setState(() {
        _otpSent = true;
        _mobileNumber = iranianMobile;
      });
      
      SnackBarHelper.show(context, message: 'کد تایید به شماره موبایل شما ارسال شد');
      
      // نمایش Dialog برای وارد کردن OTP
      final verified = await showDialog<bool>(
        context: context,
        builder: (ctx) => OtpInputDialog(
          title: 'تایید شماره موبایل',
          message: 'کد 6 رقمی ارسال شده به شماره $_mobileNumber را وارد کنید',
          onVerify: (otp) async {
            try {
              await _service.verifyMobile(otp);
              if (ctx.mounted) {
                SnackBarHelper.show(ctx, message: 'شماره موبایل با موفقیت تایید شد');
                return true;
              }
              return false;
            } catch (e) {
              SnackBarHelper.showError(context, message: 'خطا در تایید: $e');
              return false;
            }
          },
          onResend: () async {
            try {
              await _service.resendMobileVerification();
              if (ctx.mounted) {
                SnackBarHelper.show(ctx, message: 'کد جدید ارسال شد');
              }
            } catch (e) {
              SnackBarHelper.showError(context, message: 'خطا در ارسال مجدد: $e');
            }
          },
        ),
      );
      
      if (verified == true && mounted) {
        // تایید موفق - به‌روزرسانی UI
        setState(() {
          _otpSent = false;
          _mobileNumber = null;
        });
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در ارسال کد: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تایید شماره موبایل'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.phone_android,
                  size: 64,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'تایید شماره موبایل',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'برای امنیت بیشتر، لطفاً شماره موبایل خود را تایید کنید',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!_otpSent) ...[
                  _MobileInputSection(
                    onSend: _sendVerificationCode,
                    loading: _loading,
                  ),
                ] else ...[
                  Text(
                    'کد تایید به شماره $_mobileNumber ارسال شد',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _otpSent = false;
                        _mobileNumber = null;
                      });
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('تغییر شماره موبایل'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileInputSection extends StatefulWidget {
  final Future<void> Function(String mobile) onSend;
  final bool loading;

  const _MobileInputSection({
    required this.onSend,
    required this.loading,
  });

  @override
  State<_MobileInputSection> createState() => _MobileInputSectionState();
}

class _MobileInputSectionState extends State<_MobileInputSection> {
  final _mobileCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _mobileCtrl,
            enabled: !widget.loading,
            decoration: const InputDecoration(
              labelText: 'شماره موبایل',
              hintText: '09123456789',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'شماره موبایل الزامی است';
              }
              // بررسی فرمت شماره موبایل ایرانی
              final cleaned = toEnglishDigits(v.trim());
              if (!RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
                return 'شماره موبایل باید به فرمت 09123456789 باشد';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.loading
                ? null
                : () {
                    if (_formKey.currentState!.validate()) {
                      widget.onSend(_mobileCtrl.text.trim());
                    }
                  },
            icon: widget.loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('ارسال کد تایید'),
          ),
        ],
      ),
    );
  }
}

