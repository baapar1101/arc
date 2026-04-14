import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// دیالوگ مستقل و شخصی‌سازی شده برای استعلام اطلاعات هویتی
/// با ظاهری زیبا، چند زبانه و کاربرپسند
class IdentityInquiryDialog extends StatefulWidget {
  final int? businessId;

  const IdentityInquiryDialog({
    super.key,
    this.businessId,
  });

  /// نمایش دیالوگ به صورت مودال
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    int? businessId,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => IdentityInquiryDialog(
        businessId: businessId,
      ),
    );
  }

  @override
  State<IdentityInquiryDialog> createState() => _IdentityInquiryDialogState();
}

class _IdentityInquiryDialogState extends State<IdentityInquiryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nationalCodeController = TextEditingController();
  final _birthDateController = TextEditingController();
  
  bool _isSubmitting = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;
  
  // مراحل مختلف دیالوگ
  _DialogStep _currentStep = _DialogStep.input;

  @override
  void dispose() {
    _nationalCodeController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  /// اعتبارسنجی کد ملی ایرانی
  bool _isValidNationalId(String nationalId) {
    if (nationalId.length != 10) return false;
    
    // بررسی اینکه همه ارقام یکسان نباشند
    if (RegExp(r'^(\d)\1{9}$').hasMatch(nationalId)) return false;
    
    // اعتبارسنجی الگوریتم کد ملی
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(nationalId[i]) * (10 - i);
    }
    int remainder = sum % 11;
    int checkDigit = remainder < 2 ? remainder : 11 - remainder;
    
    return checkDigit == int.parse(nationalId[9]);
  }

  /// اعتبارسنجی فرمت تاریخ شمسی
  bool _isValidJalaliDate(String date) {
    // تبدیل جداکننده‌ها به -
    String normalized = date.replaceAll('/', '-');
    
    // بررسی فرمت YYYY-MM-DD
    final regex = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$');
    if (!regex.hasMatch(normalized)) return false;
    
    final parts = normalized.split('-');
    if (parts.length != 3) return false;
    
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    
    if (year == null || month == null || day == null) return false;
    
    // بررسی محدوده‌های منطقی
    if (year < 1300 || year > 1450) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    
    return true;
  }

  /// ارسال درخواست استعلام
  Future<void> _submitInquiry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final api = ApiClient();
      
      // تبدیل تاریخ به فرمت استاندارد
      String birthDate = _birthDateController.text.trim();
      birthDate = birthDate.replaceAll('/', '-');
      
      final requestData = {
        'national_code': toEnglishDigits(_nationalCodeController.text.trim()),
        'birth_date': birthDate,
      };

      // ارسال درخواست به API
      final response = await api.post(
        '/businesses/${widget.businessId}/zohal/inquiry/national_identity_inquiry',
        data: requestData,
      );

      if (mounted) {
        setState(() {
          _result = response.data as Map<String, dynamic>?;
          _currentStep = _DialogStep.result;
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        setState(() {
          _errorMessage = e.toString();
          _isSubmitting = false;
        });
        
        SnackBarHelper.showError(
          context,
          message: '${t.inquiryErrorPrefix} ${e.toString()}',
        );
      }
    }
  }

  /// بازگشت به فرم ورودی برای استعلام جدید
  void _resetForm() {
    setState(() {
      _currentStep = _DialogStep.input;
      _result = null;
      _errorMessage = null;
      _nationalCodeController.clear();
      _birthDateController.clear();
    });
  }

  /// انتخاب تاریخ تولد
  Future<void> _selectBirthDate() async {
    final textController = TextEditingController(text: _birthDateController.text);
    await showDialog<String>(
      context: context,
      builder: (context) {
        final t = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(t.selectBirthDate),
          content: TextField(
            controller: textController,
            decoration: InputDecoration(
              labelText: t.birthDate,
              hintText: '1370-01-01',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.datetime,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  _birthDateController.text = textController.text.trim();
                }
                Navigator.pop(context);
              },
              child: Text(t.ok),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر دیالوگ
            _buildHeader(theme, t),
            
            // محتوای دیالوگ
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _currentStep == _DialogStep.input
                    ? _buildInputForm(theme, t)
                    : _buildResultView(theme, t),
              ),
            ),
            
            // دکمه‌های عملیات
            _buildActions(theme, t),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person_search,
              color: theme.colorScheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              t.identityInquiryTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: theme.colorScheme.onPrimary,
            ),
            tooltip: t.close,
          ),
        ],
      ),
    );
  }

  /// ساخت فرم ورودی
  Widget _buildInputForm(ThemeData theme, AppLocalizations t) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // توضیحات
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.identityInquirySubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // فیلد کد ملی
          TextFormField(
            controller: _nationalCodeController,
            decoration: InputDecoration(
              labelText: t.nationalId,
              hintText: '1234567890',
              prefixIcon: const Icon(Icons.badge),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              helperText: t.nationalIdHint,
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            keyboardType: TextInputType.number,
            maxLength: 10,
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return t.nationalIdRequired;
              }
              final cleaned = toEnglishDigits(value.trim());
              if (cleaned.length != 10) {
                return t.nationalIdInvalidLength;
              }
              if (!_isValidNationalId(cleaned)) {
                return t.nationalIdInvalid;
              }
              return null;
            },
          ),
          
          const SizedBox(height: 24),
          
          // فیلد تاریخ تولد
          TextFormField(
            controller: _birthDateController,
            decoration: InputDecoration(
              labelText: t.birthDate,
              hintText: '1370-01-01',
              prefixIcon: const Icon(Icons.calendar_today),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              helperText: t.birthDateHint,
              suffixIcon: IconButton(
                icon: const Icon(Icons.date_range),
                onPressed: _selectBirthDate,
                tooltip: t.selectBirthDate,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            keyboardType: TextInputType.datetime,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return t.birthDateRequired;
              }
              final cleaned = value.trim();
              if (!_isValidJalaliDate(cleaned)) {
                return t.birthDateInvalid;
              }
              return null;
            },
          ),
          
          // نمایش خطا در صورت وجود
          if (_errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ساخت نمای نتایج
  Widget _buildResultView(ThemeData theme, AppLocalizations t) {
    if (_result == null) {
      return Center(
        child: Text(t.noResultAvailable),
      );
    }

    // مسیر صحیح: _result['data']['result']['response_body']
    final responseBody = _result!['data']?['result']?['response_body'] as Map<String, dynamic>?;
    final data = responseBody?['data'] as Map<String, dynamic>?;
    final message = responseBody?['message']?.toString() ?? '';
    final errorCode = responseBody?['error_code'];

    // اگر خطا وجود دارد
    if (errorCode != null) {
      return _buildErrorResult(theme, message);
    }

    final matched = data?['matched'] as bool? ?? false;

    // اگر تطابق نداشته باشد
    if (!matched) {
      return _buildNoMatchResult(theme);
    }

    // اگر تطابق داشته باشد - نمایش اطلاعات هویتی
    return _buildSuccessResult(theme, data);
  }

  /// نمای خطا
  Widget _buildErrorResult(ThemeData theme, String message) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 24),
          Text(
            t.inquiryError,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message.isNotEmpty ? message : t.unknownError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// نمای عدم تطابق
  Widget _buildNoMatchResult(ThemeData theme) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cancel,
            size: 80,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 24),
          Text(
            t.noMatch,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.noMatchDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// نمای موفقیت
  Widget _buildSuccessResult(ThemeData theme, Map<String, dynamic>? data) {
    final firstName = data?['first_name']?.toString();
    final lastName = data?['last_name']?.toString();
    final fatherName = data?['father_name']?.toString();
    final alive = data?['alive'] as bool?;
    final isDead = data?['is_dead'] as bool?;
    final nationalCode = data?['national_code']?.toString();

    return Column(
      children: [
        // هدر با نام و نام خانوادگی
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.primaryContainer.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              if (firstName != null || lastName != null)
                Text(
                  '${firstName ?? ''} ${lastName ?? ''}'.trim(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (nationalCode != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.badge,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      nationalCode,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
              // نمایش وضعیت حیات
              if (alive != null || isDead != null) ...[
                const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: (alive == true || isDead == false)
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: (alive == true || isDead == false)
                            ? Colors.green
                            : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (alive == true || isDead == false)
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 24,
                          color: (alive == true || isDead == false)
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          (alive == true || isDead == false) 
                              ? AppLocalizations.of(context).alive
                              : AppLocalizations.of(context).deceased,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: (alive == true || isDead == false)
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // کارت اطلاعات شخصی
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context).personalInformation,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (firstName != null)
                _buildInfoRow(
                  theme,
                  AppLocalizations.of(context).firstName,
                  firstName,
                  Icons.badge_outlined,
                ),
              if (lastName != null)
                _buildInfoRow(
                  theme,
                  AppLocalizations.of(context).lastName,
                  lastName,
                  Icons.badge_outlined,
                ),
              if (fatherName != null)
                _buildInfoRow(
                  theme,
                  AppLocalizations.of(context).fatherName,
                  fatherName,
                  Icons.family_restroom,
                ),
              if (nationalCode != null)
                _buildInfoRow(
                  theme,
                  AppLocalizations.of(context).nationalId,
                  nationalCode,
                  Icons.badge,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// ساخت یک ردیف اطلاعات
  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: value));
                        SnackBarHelper.show(
                          context,
                          message: '${AppLocalizations.of(context).copied}: $value',
                        );
                      },
                      tooltip: AppLocalizations.of(context).copied,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت دکمه‌های عملیات
  Widget _buildActions(ThemeData theme, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep == _DialogStep.result) ...[
            OutlinedButton.icon(
              onPressed: _resetForm,
              icon: const Icon(Icons.refresh),
              label: Text(t.newInquiry),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (_currentStep == _DialogStep.input)
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitInquiry,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isSubmitting ? t.inquiring : t.inquire),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_result),
              icon: const Icon(Icons.check),
              label: Text(t.close),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// مراحل مختلف دیالوگ
enum _DialogStep {
  input,   // فرم ورودی
  result,  // نمایش نتایج
}

