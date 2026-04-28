import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../../models/business_models.dart';
import '../../services/business_api_service.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/date_input_field.dart';
import '../../core/date_utils.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:dio/dio.dart';
import '../../services/errors/api_error.dart';
import '../../services/job_service.dart';

class NewBusinessPage extends StatefulWidget {
  final CalendarController calendarController;
  const NewBusinessPage({super.key, required this.calendarController});

  @override
  State<NewBusinessPage> createState() => _NewBusinessPageState();
}

class _NewBusinessPageState extends State<NewBusinessPage> {
  final PageController _pageController = PageController();
  final BusinessData _businessData = BusinessData();
  int _currentStep = 0;
  bool _isLoading = false;
  final int _fiscalTabIndex = 0;
  late TextEditingController _fiscalTitleController;
  List<Map<String, dynamic>> _currencies = [];
  String? _importJobId;
  int _importProgress = 0;
  String? _importMessage;

  @override
  void initState() {
    super.initState();
    widget.calendarController.addListener(_onCalendarChanged);
    _fiscalTitleController = TextEditingController();
    // Set default selections for business type and field
    _businessData.businessType ??= BusinessType.shop;
    _businessData.businessField ??= BusinessField.commercial;
    _loadCurrencies();
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _pageController.dispose();
    _fiscalTitleController.dispose();
    super.dispose();
  }

  void _onCalendarChanged() {
    if (_businessData.fiscalYears.isEmpty) return;
    final fiscal = _businessData.fiscalYears[_fiscalTabIndex];
    if (fiscal.endDate != null) {
      const autoPrefix = 'سال مالی منتهی به';
      if (fiscal.title.trim().isEmpty || fiscal.title.trim().startsWith(autoPrefix)) {
        setState(() {
          final isJalali = widget.calendarController.isJalali;
          final endStr = HesabixDateUtils.formatForDisplay(fiscal.endDate, isJalali);
          fiscal.title = '$autoPrefix $endStr';
          _fiscalTitleController.text = fiscal.title;
        });
      }
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await BusinessApiService.getCurrencies();
      if (mounted) {
        setState(() {
          _currencies = list;
          final irr = _currencies.firstWhere(
            (e) => (e['code'] as String?) == 'IRR',
            orElse: () => {} as Map<String, dynamic>,
          );
          if (irr.isNotEmpty) {
            _businessData.defaultCurrencyId ??= irr['id'] as int?;
            if (_businessData.defaultCurrencyId != null && !_businessData.currencyIds.contains(_businessData.defaultCurrencyId)) {
              _businessData.currencyIds.add(_businessData.defaultCurrencyId!);
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _importFromBackup() async {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['hbx', 'hs60'],
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        SnackBarHelper.showError(context, message: 'فایل انتخاب شده خالی است');
        return;
      }
      
      final filename = file.name;
      final fileExt = filename.toLowerCase().split('.').last;
      
      // بررسی فایل .hs60
      if (fileExt == 'hs60') {
        SnackBarHelper.showError(
          context,
          message: 'فرمت فایل .hs60 در حال حاضر پشتیبانی نمی‌شود. این قابلیت در آینده اضافه خواهد شد.',
        );
        return;
      }
      
      setState(() {
        _isLoading = true;
        _importJobId = null;
        _importProgress = 0;
        _importMessage = null;
      });
      
      try {
        final result = await BusinessApiService.importBusinessFromBackup(
          filename: filename,
          fileBytes: file.bytes!,
          asyncMode: true,
        );
        
        final jobId = result['job_id'] as String?;
        if (jobId != null) {
          setState(() {
            _importJobId = jobId;
            _importMessage = 'در حال پردازش...';
          });
          _pollImportJob(jobId);
        } else {
          // اگر هم‌زمان بود
          final businessId = result['business_id'] as int?;
          if (businessId != null) {
            SnackBarHelper.showSuccess(context, message: 'کسب‌وکار با موفقیت از فایل پشتیبان ایجاد شد');
            if (mounted) {
              context.goNamed('profile_businesses');
            }
          }
        }
      } on DioException catch (e) {
        String errorMessage = 'خطا در ایمپورت فایل پشتیبان';
        if (e.response?.data != null) {
          final errorData = e.response!.data;
          if (errorData is Map) {
            final error = errorData['error'];
            if (error is Map) {
              errorMessage = error['message'] ?? errorMessage;
            } else if (errorData['message'] != null) {
              errorMessage = errorData['message'];
            }
          }
        }
        SnackBarHelper.showError(context, message: errorMessage);
      } catch (e) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در ایمپورت: ${ErrorExtractor.forContext(e, context)}',
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message:
              'خطا در انتخاب فایل: ${ErrorExtractor.forContext(e, context)}',
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _pollImportJob(String jobId) async {
    final jobService = JobService();
    
    while (mounted && _importJobId == jobId) {
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final status = await jobService.getJobStatus(jobId);
        final progress = status['progress'] as int? ?? 0;
        final message = status['message'] as String? ?? '';
        final state = status['state'] as String? ?? '';
        
        if (mounted) {
          setState(() {
            _importProgress = progress;
            _importMessage = message;
          });
        }
        
        if (state == 'completed') {
          final result = status['result'];
          if (result != null && result['business_id'] != null) {
            if (mounted) {
              SnackBarHelper.showSuccess(context, message: 'کسب‌وکار با موفقیت از فایل پشتیبان ایجاد شد');
              context.goNamed('profile_businesses');
            }
          }
          break;
        } else if (state == 'failed') {
          final error = status['error'] as String? ?? 'خطا در ایمپورت';
          if (mounted) {
            SnackBarHelper.showError(context, message: error);
          }
          break;
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message:
                'خطا در بررسی وضعیت: ${ErrorExtractor.forContext(e, context)}',
          );
        }
        break;
      }
    }
    
    if (mounted) {
      setState(() {
        _importJobId = null;
        _isLoading = false;
      });
    }
  }

  Widget _buildFiscalStep() {
    if (_businessData.fiscalYears.isEmpty) {
      _businessData.fiscalYears.add(FiscalYearData(isLast: true));
    }
    final fiscal = _businessData.fiscalYears[_fiscalTabIndex];

    String autoTitle() {
      final isJalali = widget.calendarController.isJalali;
      final end = fiscal.endDate;
      if (end == null) return fiscal.title;
      final endStr = HesabixDateUtils.formatForDisplay(end, isJalali);
      return 'سال مالی منتهی به $endStr';
    }

    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سال مالی',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: spacing),
              Container(
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 12.0,
                      tablet: 14.0,
                      desktop: 16.0,
                    ),
                  ),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DateInputField(
                            value: fiscal.startDate,
                            labelText: 'تاریخ شروع *',
                            lastDate: fiscal.endDate,
                            calendarController: widget.calendarController,
                            onChanged: (d) {
                              setState(() {
                                fiscal.startDate = d;
                                if (fiscal.startDate != null) {
                                  fiscal.endDate = HesabixDateUtils.fiscalYearInclusiveEndFromStart(
                                    fiscal.startDate!,
                                    widget.calendarController.isJalali,
                                  );
                                  fiscal.title = autoTitle();
                                  _fiscalTitleController.text = fiscal.title;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DateInputField(
                            value: fiscal.endDate,
                            labelText: 'تاریخ پایان *',
                            firstDate: fiscal.startDate,
                            calendarController: widget.calendarController,
                            onChanged: (d) {
                              setState(() {
                                fiscal.endDate = d;
                                if (fiscal.title.trim().isEmpty || fiscal.title.startsWith('سال مالی منتهی به')) {
                                  fiscal.title = autoTitle();
                                  _fiscalTitleController.text = fiscal.title;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fiscalTitleController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان سال مالی *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setState(() {
                          fiscal.title = v;
                        });
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing * 0.5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'پرکردن عنوان، تاریخ شروع و پایان الزامی است.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
  void _nextStep() {
    if (_currentStep < 4) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _canGoToNextStep() {
    switch (_currentStep) {
      case 0:
        return _businessData.isStep1Valid();
      case 1:
        return _businessData.isStep2Valid();
      case 2:
        return _businessData.isStep3Valid();
      case 3:
        return _businessData.isFiscalStepValid();
      default:
        return false;
    }
  }

  bool _isMobile(BuildContext context) {
    return ResponsiveHelper.isMobile(context);
  }

  bool _isTablet(BuildContext context) {
    return ResponsiveHelper.isTablet(context);
  }

  bool _isDesktop(BuildContext context) {
    return ResponsiveHelper.isDesktop(context);
  }

  String _getCurrentStepTitle(AppLocalizations t) {
    switch (_currentStep) {
      case 0:
        return t.businessBasicInfo;
      case 1:
        return t.businessContactInfo;
      case 2:
        return t.businessLegalInfo;
      case 3:
        return 'ارز و سال مالی';
      case 4:
        return t.businessConfirmation;
      default:
        return '';
    }
  }

  Future<void> _showVerificationRequiredDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('تایید مورد نیاز'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            const Text(
              'برای تایید ایمیل و شماره موبایل، به بخش تنظیمات حساب کاربری بروید.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('بعداً'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.verified_user),
            label: const Text('رفتن به تایید'),
          ),
        ],
      ),
    );
    
    if (result == true && mounted) {
      // هدایت به صفحه تایید
      context.go('/user/profile/verification');
    }
  }

  Future<void> _submitBusiness() async {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    if (!_businessData.isFormValid()) {
      ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
        SnackBar(
          content: Text(t.pleaseFillRequiredFields),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final created = await BusinessApiService.createBusiness(_businessData);

      if (mounted) {
        final seedFailed = _businessData.includeSampleData &&
            created.sampleDataSeeded == false &&
            (created.sampleDataError != null && created.sampleDataError!.isNotEmpty);
        ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
          SnackBar(
            content: Text(
              seedFailed
                  ? '${t.sampleDataSeedWarning}: ${created.sampleDataError}'
                  : t.businessCreatedSuccessfully,
            ),
            backgroundColor: seedFailed ? Colors.deepOrange : Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: Duration(seconds: seedFailed ? 5 : 2),
          ),
        );
        context.goNamed('profile_businesses');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      
      // بررسی خطای BUSINESS_CREATION_NOT_ALLOWED
      String? errorCode;
      String? errorMessage;
      
      if (e.error is ApiErrorDetails) {
        final apiError = e.error as ApiErrorDetails;
        errorCode = apiError.code;
        errorMessage = apiError.message;
      } else if (e.response?.data is Map<String, dynamic>) {
        final data = e.response!.data as Map<String, dynamic>;
        final errorObj = data['error'];
        if (errorObj is Map<String, dynamic>) {
          errorCode = errorObj['code']?.toString();
          errorMessage = errorObj['message']?.toString();
        }
      }
      
      if (errorCode == 'BUSINESS_CREATION_NOT_ALLOWED') {
        // نمایش Dialog راهنما
        await _showVerificationRequiredDialog(errorMessage ?? 'شما اجازه ایجاد کسب و کار را ندارید');
        return;
      }
      
      // سایر خطاها
      ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage ??
                '${t.businessCreationFailed}: ${ErrorExtractor.forContext(e, context)}',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
          SnackBar(
            content: Text(
              '${t.businessCreationFailed}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final isMobile = _isMobile(context);
    final isTablet = _isTablet(context);
    final isDesktop = _isDesktop(context);
    final padding = ResponsiveHelper.getPadding(context);
    
    return Scaffold(
      appBar: isMobile ? AppBar(
        title: Text(t.newBusiness),
        centerTitle: true,
        elevation: 0,
      ) : null,
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: EdgeInsets.all(padding),
            child: Column(
              children: [
                // Progress bar
                Row(
                  children: List.generate(5, (index) {
                    final isActive = index <= _currentStep;
                    final isCurrent = index == _currentStep;
                    
                    final progressHeight = ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 4.0,
                      tablet: 5.0,
                      desktop: 6.0,
                    );
                    final progressMargin = ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 1.0,
                      tablet: 1.5,
                      desktop: 2.0,
                    );
                    final borderRadius = ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 2.0,
                      tablet: 2.5,
                      desktop: 3.0,
                    );
                    
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: EdgeInsets.symmetric(horizontal: progressMargin),
                        height: progressHeight,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(borderRadius),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
                SizedBox(height: ResponsiveHelper.responsiveValue(context, mobile: 8.0, tablet: 10.0, desktop: 12.0)),
                // Progress text
                Text(
                  '${t.step} ${_currentStep + 1} ${t.ofText} 5',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Step indicator - برای تبلت و دسکتاپ
          if (!isMobile)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: ResponsiveHelper.responsiveValue(context, mobile: 8.0, tablet: 10.0, desktop: 12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStepIndicator(0, t.businessBasicInfo, isTablet),
                  _buildStepIndicator(1, t.businessContactInfo, isTablet),
                  _buildStepIndicator(2, t.businessLegalInfo, isTablet),
                  _buildStepIndicator(3, 'ارز و سال مالی', isTablet),
                  _buildStepIndicator(4, t.businessConfirmation, isTablet),
                ],
              ),
            ),
          
          // Current step title for mobile
          if (isMobile)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${_currentStep + 1}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.responsiveValue(context, mobile: 12.0, tablet: 14.0, desktop: 16.0)),
                  Expanded(
                    child: Text(
                      _getCurrentStepTitle(t),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Form content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentStep = index;
                });
              },
              children: [
                SingleChildScrollView(child: _buildStep1()),
                SingleChildScrollView(child: _buildStep2()),
                SingleChildScrollView(child: _buildStep3()),
                SingleChildScrollView(child: _buildCurrencyAndFiscalStep()),
                SingleChildScrollView(child: _buildStep4()),
              ],
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: isMobile 
                ? Column(
                    children: [
                      // Next/Submit button - full width on mobile
                      SizedBox(
                        width: double.infinity,
                        child: _buildNavigationButton(
                          text: _currentStep < 4 ? t.next : t.createBusiness,
                          icon: _currentStep < 4 ? Icons.arrow_forward_ios : Icons.check,
                          onPressed: _currentStep < 4 
                              ? (_canGoToNextStep() ? _nextStep : null)
                              : (_isLoading ? null : _submitBusiness),
                          isPrimary: true,
                          isLoading: _isLoading,
                        ),
                      ),
                      // Previous button - full width on mobile
                      if (_currentStep > 0) ...[
                        SizedBox(height: ResponsiveHelper.responsiveValue(context, mobile: 12.0, tablet: 14.0, desktop: 16.0)),
                        SizedBox(
                          width: double.infinity,
                          child: _buildNavigationButton(
                            text: t.previous,
                            icon: Icons.arrow_back_ios,
                            onPressed: _previousStep,
                            isPrimary: false,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildNavigationButton(
                        text: t.previous,
                        icon: Icons.arrow_back_ios,
                        onPressed: _currentStep > 0 ? _previousStep : null,
                        isPrimary: false,
                      ),
                      Row(
                        children: [
                          if (_currentStep < 4) ...[
                            _buildNavigationButton(
                              text: t.next,
                              icon: Icons.arrow_forward_ios,
                              onPressed: _canGoToNextStep() ? _nextStep : null,
                              isPrimary: true,
                            ),
                          ] else ...[
                            _buildNavigationButton(
                              text: t.createBusiness,
                              icon: Icons.check,
                              onPressed: _isLoading ? null : _submitBusiness,
                              isPrimary: true,
                              isLoading: _isLoading,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String title, bool isCompact) {
    final isActive = step <= _currentStep;
    final isCurrent = step == _currentStep;
    
    final iconSize = ResponsiveHelper.responsiveValue(
      context,
      mobile: 20.0,
      tablet: 22.0,
      desktop: 24.0,
    );
    final fontSize = ResponsiveHelper.responsiveValue(
      context,
      mobile: 11.0,
      tablet: 11.5,
      desktop: 12.0,
    );
    final horizontalPadding = ResponsiveHelper.responsiveValue(
      context,
      mobile: 8.0,
      tablet: 10.0,
      desktop: 12.0,
    );
    
    final isDesktop = _isDesktop(context);
    
    // برای تبلت، عنوان را کوتاه‌تر یا فقط آیکون نشان می‌دهیم
    String displayTitle = title;
    if (isCompact && !isDesktop && title.length > 12) {
      // برای تبلت، عنوان‌های طولانی را کوتاه می‌کنیم
      displayTitle = title.substring(0, 12) + '...';
    }
    
    return GestureDetector(
      onTap: () => _goToStep(step),
      child: Tooltip(
        message: title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: ResponsiveHelper.responsiveValue(context, mobile: 6.0, tablet: 8.0, desktop: 8.0),
          ),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                  shape: BoxShape.circle,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ]
                      : isActive
                          ? [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 3,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                ),
                child: Center(
                  child: isActive
                      ? Icon(
                          Icons.check,
                          size: iconSize * 0.65,
                          color: Colors.white,
                        )
                      : Text(
                          '${step + 1}',
                          style: TextStyle(
                            color: isActive
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              if (!isCompact || isDesktop) ...[
                SizedBox(width: ResponsiveHelper.responsiveValue(context, mobile: 6.0, tablet: 8.0, desktop: 8.0)),
                Text(
                  displayTitle,
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: fontSize,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required String text,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 48,
      constraints: const BoxConstraints(minWidth: 120),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Theme.of(context).primaryColor
              : Theme.of(context).colorScheme.surface,
          foregroundColor: isPrimary
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
          elevation: isPrimary ? 2 : 0,
          shadowColor: isPrimary
              ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                    width: 1,
                  ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          animationDuration: const Duration(milliseconds: 200),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isLoading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPrimary ? Colors.white : Theme.of(context).primaryColor,
                    ),
                  ),
                )
              : Row(
                  key: ValueKey('content_$text'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPrimary) ...[
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        icon,
                        size: 18,
                      ),
                    ] else ...[
                      Icon(
                        icon,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // دکمه ایمپورت از فایل پشتیبان
                Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: _isLoading ? null : _importFromBackup,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: EdgeInsets.all(spacing),
                      child: Row(
                        children: [
                          Icon(
                            Icons.upload_file,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(width: spacing * 0.5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ایجاد از فایل پشتیبان',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'آپلود فایل .hbx برای ایجاد کسب‌وکار',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isLoading && _importJobId != null)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _importProgress / 100,
                              ),
                            )
                          else if (_isLoading)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_importMessage != null) ...[
                  SizedBox(height: spacing * 0.5),
                  Text(
                    _importMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                SizedBox(height: spacing),
                Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: spacing * 0.5),
                      child: Text(
                        'یا',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: spacing),
                Text(
                  t.businessBasicInfo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: spacing),
                
                // نام کسب و کار
                TextFormField(
                  decoration: InputDecoration(
                    labelText: '${t.businessName} *',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _businessData.name = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '${t.businessName} ${t.required}';
                    }
                    return null;
                  },
                ),
                SizedBox(height: spacing),
                
                // نوع کسب و کار
                DropdownButtonFormField<BusinessType>(
                  decoration: InputDecoration(
                    labelText: '${t.businessType} *',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  initialValue: _businessData.businessType,
                  items: BusinessType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _businessData.businessType = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return '${t.businessType} ${t.required}';
                    }
                    return null;
                  },
                ),
                SizedBox(height: spacing),
                
                // زمینه فعالیت
                DropdownButtonFormField<BusinessField>(
                  decoration: InputDecoration(
                    labelText: '${t.businessField} *',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  initialValue: _businessData.businessField,
                  items: BusinessField.values.map((field) {
                    return DropdownMenuItem(
                      value: field,
                      child: Text(field.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _businessData.businessField = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return '${t.businessField} ${t.required}';
                    }
                    return null;
                  },
                ),
                SizedBox(height: spacing),
                CheckboxListTile(
                  value: _businessData.includeSampleData,
                  onChanged: _isLoading
                      ? null
                      : (v) {
                          setState(() {
                            _businessData.includeSampleData = v ?? false;
                          });
                        },
                  title: Text(t.includeSampleDataLabel),
                  subtitle: Text(
                    t.includeSampleDataSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );
    final isTablet = _isTablet(context);
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                  t.businessContactInfo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: spacing),
                
                // آدرس - تمام عرض
                TextFormField(
                  decoration: InputDecoration(
                    labelText: t.address,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    setState(() {
                      _businessData.address = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // فیلدهای تماس در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fieldSpacing = ResponsiveHelper.getGridSpacing(context);
                    if (!_isMobile(context)) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: t.phone,
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                ),
                                errorText: _businessData.getValidationError('phone'),
                                helperText: '${t.example}: ${t.phoneExample}',
                              ),
                              keyboardType: TextInputType.phone,
                              inputFormatters: const [EnglishDigitsFormatter()],
                              onChanged: (value) {
                                setState(() {
                                  _businessData.phone = toEnglishDigits(value);
                                });
                              },
                            ),
                          ),
                          SizedBox(width: fieldSpacing),
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: t.mobile,
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                ),
                                errorText: _businessData.getValidationError('mobile'),
                                helperText: '${t.example}: ${t.mobileExample}',
                              ),
                              keyboardType: TextInputType.phone,
                              inputFormatters: const [EnglishDigitsFormatter()],
                              onChanged: (value) {
                                setState(() {
                                  _businessData.mobile = toEnglishDigits(value);
                                });
                              },
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.phone,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                              errorText: _businessData.getValidationError('phone'),
                              helperText: '${t.example}: ${t.phoneExample}',
                            ),
                            keyboardType: TextInputType.phone,
                            inputFormatters: const [EnglishDigitsFormatter()],
                            onChanged: (value) {
                              setState(() {
                                _businessData.phone = toEnglishDigits(value);
                              });
                            },
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.mobile,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                              errorText: _businessData.getValidationError('mobile'),
                              helperText: '${t.example}: ${t.mobileExample}',
                            ),
                            keyboardType: TextInputType.phone,
                            inputFormatters: const [EnglishDigitsFormatter()],
                            onChanged: (value) {
                              setState(() {
                                _businessData.mobile = toEnglishDigits(value);
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
                SizedBox(height: spacing),
                
                // کد پستی
                TextFormField(
                  decoration: InputDecoration(
                    labelText: t.postalCode,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                inputFormatters: [
                  EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.digitsOnly,
                ],
                  onChanged: (value) {
                    setState(() {
                    _businessData.postalCode = toEnglishDigits(value);
                    });
                  },
                ),
                SizedBox(height: spacing * 1.5),
                
                // فیلدهای جغرافیایی
                Text(
                  t.businessGeographicInfo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(height: spacing),
                
                // فیلدهای جغرافیایی در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fieldSpacing = ResponsiveHelper.getGridSpacing(context);
                    if (!_isMobile(context)) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: t.country,
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.country = value;
                                    });
                                  },
                                ),
                              ),
                              SizedBox(width: fieldSpacing),
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: t.province,
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.province = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.city,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.city = value;
                              });
                            },
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.country,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.country = value;
                              });
                            },
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.province,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.province = value;
                              });
                            },
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.city,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.city = value;
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep3() {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                  t.businessLegalInfo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: spacing),
                
                // فیلدهای قانونی در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fieldSpacing = ResponsiveHelper.getGridSpacing(context);
                    if (!_isMobile(context)) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: t.nationalId,
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                    errorText: _businessData.getValidationError('nationalId'),
                                    helperText: '${t.example}: ${t.nationalIdExample}',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.nationalId = value;
                                    });
                                  },
                                ),
                              ),
                              SizedBox(width: fieldSpacing),
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: t.registrationNumber,
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  keyboardType: TextInputType.text,
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.registrationNumber = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.economicId,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.economicId = value;
                              });
                            },
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.nationalId,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                              errorText: _businessData.getValidationError('nationalId'),
                              helperText: '${t.example}: ${t.nationalIdExample}',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              EnglishDigitsFormatter(),
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) {
                              setState(() {
                                _businessData.nationalId = toEnglishDigits(value);
                              });
                            },
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.registrationNumber,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.registrationNumber = value;
                              });
                            },
                          ),
                          SizedBox(height: spacing),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.economicId,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.economicId = value;
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyAndFiscalStep() {
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ارز و سال مالی',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: spacing),
              Container(
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 12.0,
                      tablet: 14.0,
                      desktop: 16.0,
                    ),
                  ),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _businessData.defaultCurrencyId,
                      items: _currencies.map((c) {
                        return DropdownMenuItem<int>(
                          value: c['id'] as int,
                          child: Text('${c['title']} (${c['code']})'),
                        );
                      }).toList(),
                      decoration: const InputDecoration(
                        labelText: 'ارز پیشفرض *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setState(() {
                          _businessData.defaultCurrencyId = v;
                          if (v != null && !_businessData.currencyIds.contains(v)) {
                            _businessData.currencyIds.add(v);
                          }
                        });
                      },
                    ),
                    SizedBox(height: spacing * 0.75),
                    _CurrencyMultiSelect(
                      currencies: _currencies,
                      selectedIds: _businessData.currencyIds,
                      defaultId: _businessData.defaultCurrencyId,
                      onChanged: (ids) {
                        setState(() {
                          _businessData.currencyIds = ids;
                          final d = _businessData.defaultCurrencyId;
                          if (d != null && !_businessData.currencyIds.contains(d)) {
                            _businessData.currencyIds.add(d);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing * 1.5),
              _buildFiscalStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep4() {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );
    final isTablet = _isTablet(context);
    final isDesktop = _isDesktop(context);
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getCardMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                  t.confirmInfo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: spacing * 1.5),
                
                // نمایش خلاصه اطلاعات
                Container(
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(
                      ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 12.0,
                        tablet: 14.0,
                        desktop: 16.0,
                      ),
                    ),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // برای دسکتاپ و تبلت بزرگ، از دو ستون استفاده می‌کنیم
                      if (isDesktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSummaryItem(t.businessName, _businessData.name),
                                  _buildSummaryItem(t.businessType, _businessData.businessType?.displayName ?? ''),
                                  _buildSummaryItem(t.businessField, _businessData.businessField?.displayName ?? ''),
                                  if (_businessData.address?.isNotEmpty == true)
                                    _buildSummaryItem(t.address, _businessData.address!),
                                  if (_businessData.phone?.isNotEmpty == true)
                                    _buildSummaryItem(t.phone, _businessData.phone!),
                                  if (_businessData.mobile?.isNotEmpty == true)
                                    _buildSummaryItem(t.mobile, _businessData.mobile!),
                                  if (_businessData.postalCode?.isNotEmpty == true)
                                    _buildSummaryItem(t.postalCode, _businessData.postalCode!),
                                ],
                              ),
                            ),
                            SizedBox(width: spacing),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_businessData.nationalId?.isNotEmpty == true)
                                    _buildSummaryItem(t.nationalId, _businessData.nationalId!),
                                  if (_businessData.registrationNumber?.isNotEmpty == true)
                                    _buildSummaryItem(t.registrationNumber, _businessData.registrationNumber!),
                                  if (_businessData.economicId?.isNotEmpty == true)
                                    _buildSummaryItem(t.economicId, _businessData.economicId!),
                                  if (_businessData.country?.isNotEmpty == true)
                                    _buildSummaryItem(t.country, _businessData.country!),
                                  if (_businessData.province?.isNotEmpty == true)
                                    _buildSummaryItem(t.province, _businessData.province!),
                                  if (_businessData.city?.isNotEmpty == true)
                                    _buildSummaryItem(t.city, _businessData.city!),
                                  if (_businessData.fiscalYears.isNotEmpty)
                                    _buildSummaryItem('سال مالی', _businessData.fiscalYears.first.title),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryItem(t.businessName, _businessData.name),
                            _buildSummaryItem(t.businessType, _businessData.businessType?.displayName ?? ''),
                            _buildSummaryItem(t.businessField, _businessData.businessField?.displayName ?? ''),
                            if (_businessData.address?.isNotEmpty == true)
                              _buildSummaryItem(t.address, _businessData.address!),
                            if (_businessData.phone?.isNotEmpty == true)
                              _buildSummaryItem(t.phone, _businessData.phone!),
                            if (_businessData.mobile?.isNotEmpty == true)
                              _buildSummaryItem(t.mobile, _businessData.mobile!),
                            if (_businessData.nationalId?.isNotEmpty == true)
                              _buildSummaryItem(t.nationalId, _businessData.nationalId!),
                            if (_businessData.registrationNumber?.isNotEmpty == true)
                              _buildSummaryItem(t.registrationNumber, _businessData.registrationNumber!),
                            if (_businessData.economicId?.isNotEmpty == true)
                              _buildSummaryItem(t.economicId, _businessData.economicId!),
                            if (_businessData.country?.isNotEmpty == true)
                              _buildSummaryItem(t.country, _businessData.country!),
                            if (_businessData.province?.isNotEmpty == true)
                              _buildSummaryItem(t.province, _businessData.province!),
                            if (_businessData.city?.isNotEmpty == true)
                              _buildSummaryItem(t.city, _businessData.city!),
                            if (_businessData.postalCode?.isNotEmpty == true)
                              _buildSummaryItem(t.postalCode, _businessData.postalCode!),
                            if (_businessData.fiscalYears.isNotEmpty)
                              _buildSummaryItem('سال مالی', _businessData.fiscalYears.first.title),
                          ],
                        );
                      }
                    },
                  ),
                ),
                SizedBox(height: spacing * 1.5),
                
                // پیام تأیید
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).primaryColor,
                      size: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 20.0,
                        tablet: 22.0,
                        desktop: 24.0,
                      ),
                    ),
                    SizedBox(width: spacing * 0.5),
                    Expanded(
                      child: Text(
                        t.confirmInfoMessage,
                        style: TextStyle(
                          fontSize: ResponsiveHelper.responsiveValue(
                            context,
                            mobile: 14.0,
                            tablet: 15.0,
                            desktop: 16.0,
                          ),
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 8.0,
      tablet: 10.0,
      desktop: 12.0,
    );
    final labelWidth = ResponsiveHelper.responsiveValue(
      context,
      mobile: 100.0,
      tablet: 120.0,
      desktop: 140.0,
    );
    
    return Padding(
      padding: EdgeInsets.only(bottom: spacing * 0.75),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: ResponsiveHelper.responsiveValue(
                  context,
                  mobile: 13.0,
                  tablet: 14.0,
                  desktop: 14.0,
                ),
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          SizedBox(width: spacing * 0.5),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: ResponsiveHelper.responsiveValue(
                  context,
                  mobile: 13.0,
                  tablet: 14.0,
                  desktop: 14.0,
                ),
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyMultiSelect extends StatefulWidget {
  final List<Map<String, dynamic>> currencies;
  final List<int> selectedIds;
  final int? defaultId;
  final ValueChanged<List<int>> onChanged;

  const _CurrencyMultiSelect({
    required this.currencies,
    required this.selectedIds,
    required this.defaultId,
    required this.onChanged,
  });

  @override
  State<_CurrencyMultiSelect> createState() => _CurrencyMultiSelectState();
}

class _CurrencyMultiSelectState extends State<_CurrencyMultiSelect> {
  late List<int> _selected;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _panelOpen = false;

  @override
  void initState() {
    super.initState();
    _selected = List<int>.from(widget.selectedIds);
  }

  @override
  void didUpdateWidget(covariant _CurrencyMultiSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _selected = List<int>.from(widget.selectedIds);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        if (widget.defaultId != id) {
          _selected.remove(id);
        }
      } else {
        _selected.add(id);
      }
      widget.onChanged(List<int>.from(_selected));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.currencies.where((c) {
      final q = _searchCtrl.text.trim();
      if (q.isEmpty) return true;
      final title = (c['title'] ?? '').toString();
      final code = (c['code'] ?? '').toString();
      return title.contains(q) || code.toLowerCase().contains(q.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ارزهای جانبی', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _panelOpen = !_panelOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surface,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selected.isEmpty
                        ? [
                            Text(
                              'انتخاب کنید...',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.hintColor,
                              ),
                            )
                          ]
                        : _selected.map((id) {
                            final c = widget.currencies.firstWhere((e) => e['id'] == id, orElse: () => {});
                            final isDefault = widget.defaultId == id;
                            return Chip(
                              label: Text('${c['title']} (${c['code']})'),
                              avatar: isDefault ? const Icon(Icons.star, size: 16) : null,
                              onDeleted: isDefault ? null : () => _toggle(id),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(_panelOpen ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_panelOpen) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'جستجو بر اساس نام یا کد...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final c = filtered[index];
                  final id = c['id'] as int;
                  final selected = _selected.contains(id);
                  final isDefault = widget.defaultId == id;
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (val) => _toggle(id),
                    dense: true,
                    title: Text('${c['title']} (${c['code']})'),
                    secondary: isDefault ? const Icon(Icons.star, size: 18) : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}