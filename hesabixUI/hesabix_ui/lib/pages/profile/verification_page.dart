import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../services/verification_service.dart';
import '../../widgets/auth/otp_input_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_normalizer.dart' show toEnglishDigits;
import '../../services/errors/api_error.dart';
import 'package:dio/dio.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _service = VerificationService(ApiClient());
  
  // User info
  Map<String, dynamic>? _userInfo;
  bool _loadingUserInfo = true;
  
  // Mobile section
  final _mobileCtrl = TextEditingController();
  bool _editMobileEnabled = false;
  bool _mobileLoading = false;
  String? _mobileCaptchaId;
  Uint8List? _mobileCaptchaImage;
  Timer? _mobileCaptchaTimer;
  final _mobileCaptchaCtrl = TextEditingController();
  
  // Email section
  final _emailCtrl = TextEditingController();
  bool _editEmailEnabled = false;
  bool _emailLoading = false;
  String? _emailCaptchaId;
  Uint8List? _emailCaptchaImage;
  Timer? _emailCaptchaTimer;
  final _emailCaptchaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCaptchaCtrl.dispose();
    _emailCaptchaCtrl.dispose();
    _mobileCaptchaTimer?.cancel();
    _emailCaptchaTimer?.cancel();
    super.dispose();
  }

  String _normalizeMobileForDisplay(String? mobile) {
    if (mobile == null || mobile.isEmpty) return '';
    
    final normalized = toEnglishDigits(mobile.trim().replaceAll(RegExp(r'[\s\-\(\)]'), ''));
    
    // تبدیل فرمت‌های مختلف به فرمت 0912...
    if (normalized.startsWith('+989')) {
      return '0${normalized.substring(4)}'; // +989123456789 -> 09123456789
    } else if (normalized.startsWith('00989')) {
      return '0${normalized.substring(5)}'; // 00989123456789 -> 09123456789
    } else if (normalized.startsWith('989') && normalized.length >= 12) {
      return '0${normalized.substring(3)}'; // 989123456789 -> 09123456789
    } else if (normalized.startsWith('9') && normalized.length == 10) {
      return '0$normalized'; // 9123456789 -> 09123456789
    }
    
    // اگر قبلاً در فرمت 0912... است، همان را برمی‌گرداند
    return normalized;
  }

  Future<void> _loadUserInfo() async {
    setState(() {
      _loadingUserInfo = true;
    });
    
    try {
      final userInfo = await _service.getUserInfo();
      if (!mounted) return;
      
      setState(() {
        _userInfo = userInfo;
        // تبدیل شماره موبایل به فرمت نمایش (0912...) برای فیلد ورودی
        final mobileRaw = userInfo['mobile']?.toString();
        _mobileCtrl.text = _normalizeMobileForDisplay(mobileRaw);
        _emailCtrl.text = userInfo['email']?.toString() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در دریافت اطلاعات: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingUserInfo = false;
        });
      }
    }
  }

  Future<void> _refreshCaptcha(String type) async {
    try {
      final captchaData = await _service.getCaptcha();
      final String? id = captchaData['captcha_id']?.toString();
      final String? imgB64 = captchaData['image_base64']?.toString();
      final int? ttl = (captchaData['ttl_seconds'] as num?)?.toInt();
      
      if (id == null || imgB64 == null) return;
      
      Uint8List bytes;
      try {
        bytes = base64Decode(imgB64);
      } catch (_) {
        return;
      }
      
      if (!mounted) return;
      setState(() {
        if (type == 'mobile') {
          _mobileCaptchaId = id;
          _mobileCaptchaImage = bytes;
        } else if (type == 'email') {
          _emailCaptchaId = id;
          _emailCaptchaImage = bytes;
        }
      });
      
      if (ttl != null && ttl > 0) {
        final delay = Duration(seconds: ttl);
        if (type == 'mobile') {
          _mobileCaptchaTimer?.cancel();
          _mobileCaptchaTimer = Timer(delay, () => _refreshCaptcha('mobile'));
        } else if (type == 'email') {
          _emailCaptchaTimer?.cancel();
          _emailCaptchaTimer = Timer(delay, () => _refreshCaptcha('email'));
        }
      }
    } catch (_) {
      // Silent error
    }
  }

  Future<void> _updateMobile() async {
    if (_mobileCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً شماره موبایل را وارد کنید');
      return;
    }
    
    if (_mobileCaptchaId == null || _mobileCaptchaCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً کد کپچا را وارد کنید');
      return;
    }

    // نرمال‌سازی شماره موبایل - پشتیبانی از همه فرمت‌ها
    final cleanedMobile = toEnglishDigits(_mobileCtrl.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), ''));
    String iranianMobile = cleanedMobile;
    
    // تبدیل فرمت‌های مختلف به فرمت 0912...
    if (iranianMobile.startsWith('+989')) {
      iranianMobile = '0${iranianMobile.substring(4)}'; // +989 -> 0
    } else if (iranianMobile.startsWith('00989')) {
      iranianMobile = '0${iranianMobile.substring(5)}'; // 00989 -> 0
    } else if (iranianMobile.startsWith('989') && iranianMobile.length >= 12) {
      iranianMobile = '0${iranianMobile.substring(3)}'; // 989 -> 0
    } else if (iranianMobile.startsWith('9') && iranianMobile.length == 10) {
      iranianMobile = '0$iranianMobile';
    }
    
    // اعتبارسنجی فرمت نهایی (باید 0912... باشد)
    if (!RegExp(r'^09\d{9}$').hasMatch(iranianMobile)) {
      SnackBarHelper.showError(context, message: 'شماره موبایل نامعتبر است. فرمت صحیح: 09123456789 یا +989123456789');
      return;
    }

    setState(() {
      _mobileLoading = true;
    });

    try {
      await _service.updateMobile(
        mobile: iranianMobile,
        captchaId: _mobileCaptchaId!,
        captchaCode: _mobileCaptchaCtrl.text.trim(),
        forceUnverified: false,
      );
      
      if (!mounted) return;
      
      // به‌روزرسانی اطلاعات کاربر
      await _loadUserInfo();
      
      SnackBarHelper.show(context, message: 'شماره موبایل با موفقیت به‌روزرسانی شد');
      await _openMobileOtpDialog(iranianMobile);
    } on DioException catch (e) {
      if (!mounted) return;
      
      String errorMessage = 'خطا در به‌روزرسانی شماره موبایل';
      String? errorCode;
      
      if (e.error is ApiErrorDetails) {
        final apiError = e.error as ApiErrorDetails;
        errorMessage = apiError.message ?? errorMessage;
        errorCode = apiError.code;
      } else if (e.response?.data is Map<String, dynamic>) {
        final data = e.response!.data as Map<String, dynamic>;
        final errorObj = data['error'];
        if (errorObj is Map<String, dynamic>) {
          errorMessage = errorObj['message']?.toString() ?? errorMessage;
          errorCode = errorObj['code']?.toString();
        }
      }
      
      // بررسی خطاهای خاص
      if (errorCode == 'MOBILE_IN_USE_VERIFIED') {
        SnackBarHelper.showError(context, message: errorMessage);
      } else if (errorCode == 'MOBILE_IN_USE_UNVERIFIED') {
        // نمایش Dialog برای تایید
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ هشدار'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ادامه'),
              ),
            ],
          ),
        );
        
        if (confirmed == true && mounted) {
          // تلاش مجدد با force_unverified
          try {
            await _service.updateMobile(
              mobile: iranianMobile,
              captchaId: _mobileCaptchaId!,
              captchaCode: _mobileCaptchaCtrl.text.trim(),
              forceUnverified: true,
            );
            
            if (!mounted) return;
            await _loadUserInfo();
            SnackBarHelper.show(context, message: 'شماره موبایل با موفقیت به‌روزرسانی شد');
            await _openMobileOtpDialog(iranianMobile);
          } catch (e2) {
            if (mounted) {
              SnackBarHelper.showError(context, message: 'خطا: $e2');
            }
          }
        }
      } else {
        SnackBarHelper.showError(context, message: errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در به‌روزرسانی شماره موبایل: $e');
    } finally {
      if (mounted) {
        setState(() {
          _mobileLoading = false;
          _mobileCaptchaCtrl.clear();
        });
      }
    }
  }

  /// کد تایید از سمت سرور پس از update-mobile (send_verification_sms) ارسال می‌شود؛ فقط وارد کردن OTP را نمایش می‌دهد.
  Future<void> _openMobileOtpDialog(String mobile) async {
    try {
      if (!mounted) return;
      final verified = await showDialog<bool>(
        context: context,
        builder: (ctx) => OtpInputDialog(
          title: 'تایید شماره موبایل',
          message: 'کد 6 رقمی ارسال شده به شماره $mobile را وارد کنید',
          onVerify: (otp) async {
            try {
              await _service.verifyMobile(otp);
              if (ctx.mounted) {
                SnackBarHelper.show(ctx, message: 'شماره موبایل با موفقیت تایید شد');
                return true;
              }
              return false;
            } catch (e) {
              SnackBarHelper.showError(ctx, message: 'خطا در تایید: $e');
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
              SnackBarHelper.showError(ctx, message: 'خطا در ارسال مجدد: $e');
            }
          },
        ),
      );
      
      if (verified == true && mounted) {
        await _loadUserInfo();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _updateEmail() async {
    if (_emailCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً ایمیل را وارد کنید');
      return;
    }
    
    if (_emailCaptchaId == null || _emailCaptchaCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً کد کپچا را وارد کنید');
      return;
    }

    // اعتبارسنجی فرمت ایمیل
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(_emailCtrl.text.trim())) {
      SnackBarHelper.showError(context, message: 'ایمیل نامعتبر است');
      return;
    }

    setState(() {
      _emailLoading = true;
    });

    try {
      await _service.updateEmail(
        email: _emailCtrl.text.trim(),
        captchaId: _emailCaptchaId!,
        captchaCode: _emailCaptchaCtrl.text.trim(),
        forceUnverified: false,
      );
      
      if (!mounted) return;
      
      // به‌روزرسانی اطلاعات کاربر
      await _loadUserInfo();
      
      SnackBarHelper.show(context, message: 'ایمیل با موفقیت به‌روزرسانی شد');
      
      // ارسال ایمیل تایید
      await _service.sendEmailVerification();
      if (mounted) {
        SnackBarHelper.show(context, message: 'ایمیل تایید ارسال شد. لطفاً صندوق ورودی خود را بررسی کنید.');
      }
      
    } on DioException catch (e) {
      if (!mounted) return;
      
      String errorMessage = 'خطا در به‌روزرسانی ایمیل';
      String? errorCode;
      
      if (e.error is ApiErrorDetails) {
        final apiError = e.error as ApiErrorDetails;
        errorMessage = apiError.message ?? errorMessage;
        errorCode = apiError.code;
      } else if (e.response?.data is Map<String, dynamic>) {
        final data = e.response!.data as Map<String, dynamic>;
        final errorObj = data['error'];
        if (errorObj is Map<String, dynamic>) {
          errorMessage = errorObj['message']?.toString() ?? errorMessage;
          errorCode = errorObj['code']?.toString();
        }
      }
      
      // بررسی خطاهای خاص
      if (errorCode == 'EMAIL_IN_USE_VERIFIED') {
        SnackBarHelper.showError(context, message: errorMessage);
      } else if (errorCode == 'EMAIL_IN_USE_UNVERIFIED') {
        // نمایش Dialog برای تایید
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ هشدار'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ادامه'),
              ),
            ],
          ),
        );
        
        if (confirmed == true && mounted) {
          // تلاش مجدد با force_unverified
          try {
            await _service.updateEmail(
              email: _emailCtrl.text.trim(),
              captchaId: _emailCaptchaId!,
              captchaCode: _emailCaptchaCtrl.text.trim(),
              forceUnverified: true,
            );
            
            if (!mounted) return;
            await _loadUserInfo();
            SnackBarHelper.show(context, message: 'ایمیل با موفقیت به‌روزرسانی شد');
            await _service.sendEmailVerification();
            if (mounted) {
              SnackBarHelper.show(context, message: 'ایمیل تایید ارسال شد');
            }
          } catch (e2) {
            if (mounted) {
              SnackBarHelper.showError(context, message: 'خطا: $e2');
            }
          }
        }
      } else {
        SnackBarHelper.showError(context, message: errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در به‌روزرسانی ایمیل: $e');
    } finally {
      if (mounted) {
        setState(() {
          _emailLoading = false;
          _emailCaptchaCtrl.clear();
        });
      }
    }
  }

  String _maskMobile(String? mobile) {
    if (mobile == null || mobile.isEmpty) return '';
    if (mobile.length < 4) return mobile;
    return '${mobile.substring(0, 3)}****${mobile.substring(mobile.length - 3)}';
  }

  String _maskEmail(String? email) {
    if (email == null || email.isEmpty) return '';
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts[0];
    final domain = parts[1];
    if (local.length <= 2) {
      return '${local[0]}*@$domain';
    }
    return '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}@$domain';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUserInfo) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('تایید شماره موبایل و ایمیل'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final mobileVerified = _userInfo?['mobile_verified'] == true;
    final emailVerified = _userInfo?['email_verified'] == true;
    final mobile = _userInfo?['mobile']?.toString();
    final email = _userInfo?['email']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('تایید شماره موبایل و ایمیل'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بخش شماره موبایل
            _VerificationSection(
              title: 'شماره موبایل',
              icon: Icons.phone_android,
              value: mobile,
              maskedValue: _maskMobile(mobile),
              verified: mobileVerified,
              editEnabled: _editMobileEnabled,
              onEditToggle: (enabled) {
                setState(() {
                  _editMobileEnabled = enabled;
                  if (enabled) {
                    _refreshCaptcha('mobile');
                  }
                });
              },
              controller: _mobileCtrl,
              enabled: _editMobileEnabled && !mobileVerified,
              loading: _mobileLoading,
              captchaId: _mobileCaptchaId,
              captchaImage: _mobileCaptchaImage,
              captchaController: _mobileCaptchaCtrl,
              onRefreshCaptcha: () => _refreshCaptcha('mobile'),
              onSave: _updateMobile,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'شماره موبایل الزامی است';
                }
                final cleaned = toEnglishDigits(v.trim().replaceAll(RegExp(r'[\s\-\(\)]'), ''));
                
                // تبدیل به فرمت استاندارد برای بررسی
                String normalized = cleaned;
                if (normalized.startsWith('+989')) {
                  normalized = '0${normalized.substring(4)}'; // +989 -> 0
                } else if (normalized.startsWith('00989')) {
                  normalized = '0${normalized.substring(5)}'; // 00989 -> 0
                } else if (normalized.startsWith('989') && normalized.length >= 12) {
                  normalized = '0${normalized.substring(3)}'; // 989 -> 0
                } else if (normalized.startsWith('9') && normalized.length == 10) {
                  normalized = '0$normalized';
                }
                
                // بررسی فرمت نهایی (باید 0912... باشد)
                if (RegExp(r'^09\d{9}$').hasMatch(normalized)) {
                  return null; // فرمت معتبر
                }
                
                // اگر به فرمت استاندارد تبدیل نشد، بررسی فرمت‌های دیگر
                if (RegExp(r'^\+989\d{9}$').hasMatch(cleaned) ||
                    RegExp(r'^00989\d{9}$').hasMatch(cleaned) ||
                    RegExp(r'^989\d{9}$').hasMatch(cleaned)) {
                  return null; // فرمت‌های دیگر هم معتبرند
                }
                
                return 'شماره موبایل نامعتبر است. فرمت صحیح: 09123456789 یا +989123456789';
              },
            ),
            const SizedBox(height: 24),
            // بخش ایمیل
            _VerificationSection(
              title: 'ایمیل',
              icon: Icons.email,
              value: email,
              maskedValue: _maskEmail(email),
              verified: emailVerified,
              editEnabled: _editEmailEnabled,
              onEditToggle: (enabled) {
                setState(() {
                  _editEmailEnabled = enabled;
                  if (enabled) {
                    _refreshCaptcha('email');
                  }
                });
              },
              controller: _emailCtrl,
              enabled: _editEmailEnabled && !emailVerified,
              loading: _emailLoading,
              captchaId: _emailCaptchaId,
              captchaImage: _emailCaptchaImage,
              captchaController: _emailCaptchaCtrl,
              onRefreshCaptcha: () => _refreshCaptcha('email'),
              onSave: _updateEmail,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'ایمیل الزامی است';
                }
                final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                if (!emailRegex.hasMatch(v.trim())) {
                  return 'ایمیل نامعتبر است';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final String? value;
  final String maskedValue;
  final bool verified;
  final bool editEnabled;
  final ValueChanged<bool> onEditToggle;
  final TextEditingController controller;
  final bool enabled;
  final bool loading;
  final String? captchaId;
  final Uint8List? captchaImage;
  final TextEditingController captchaController;
  final VoidCallback onRefreshCaptcha;
  final VoidCallback onSave;
  final String? Function(String?)? validator;

  const _VerificationSection({
    required this.title,
    required this.icon,
    required this.value,
    required this.maskedValue,
    required this.verified,
    required this.editEnabled,
    required this.onEditToggle,
    required this.controller,
    required this.enabled,
    required this.loading,
    required this.captchaId,
    required this.captchaImage,
    required this.captchaController,
    required this.onRefreshCaptcha,
    required this.onSave,
    this.validator,
  });

  @override
  State<_VerificationSection> createState() => _VerificationSectionState();
}

class _VerificationSectionState extends State<_VerificationSection> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(widget.icon, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.verified)
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    )
                  else
                    Icon(
                      Icons.warning,
                      color: Colors.orange,
                      size: 24,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.verified)
                Text(
                  '✅ تایید شده',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.green,
                  ),
                )
              else
                Text(
                  '⚠️ تایید نشده',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.orange,
                  ),
                ),
              const SizedBox(height: 8),
              if (widget.verified)
                Text(
                  widget.maskedValue,
                  style: theme.textTheme.bodyMedium,
                )
              else
                Text(
                  widget.value ?? 'ثبت نشده',
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('فعال‌سازی ویرایش'),
                  const Spacer(),
                  Switch(
                    value: widget.editEnabled,
                    onChanged: widget.verified ? null : (value) {
                      widget.onEditToggle(value);
                    },
                  ),
                ],
              ),
              if (widget.editEnabled && !widget.verified) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    labelText: widget.title,
                    prefixIcon: Icon(widget.icon),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: false,
                  ),
                  keyboardType: widget.title == 'ایمیل' 
                      ? TextInputType.emailAddress 
                      : TextInputType.phone,
                  validator: widget.validator,
                  inputFormatters: widget.title == 'شماره موبایل'
                      ? [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
                        ]
                      : null,
                ),
                const SizedBox(height: 16),
                // کپچا
                if (widget.captchaId != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: widget.captchaController,
                          enabled: !widget.loading,
                          decoration: const InputDecoration(
                            labelText: 'کد کپچا',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.captchaImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            widget.captchaImage!,
                            height: 40,
                            width: 120,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        const SizedBox(width: 120, height: 40),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: widget.onRefreshCaptcha,
                        tooltip: 'تازه‌سازی کپچا',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: widget.loading
                      ? null
                      : () {
                          if (_formKey.currentState!.validate()) {
                            if (widget.captchaId == null || widget.captchaController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('لطفاً کد کپچا را وارد کنید')),
                              );
                              return;
                            }
                            widget.onSave();
                          }
                        },
                  icon: widget.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(widget.title == 'شماره موبایل' 
                      ? 'به‌روزرسانی و ارسال کد تایید' 
                      : 'به‌روزرسانی و ارسال ایمیل تایید'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

