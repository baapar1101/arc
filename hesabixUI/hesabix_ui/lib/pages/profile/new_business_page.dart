import 'package:hesabix_ui/theme/glass.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../core/api_client.dart';
import '../../models/business_models.dart';
import '../../services/business_api_service.dart';
import '../../services/errors/api_error.dart';
import '../../services/job_service.dart';
import '../../services/legacy_api_import_public_config.dart';
import '../../utils/error_extractor.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/profile/legacy_import_wizard.dart';
import '../../widgets/profile/new_business/new_business_financial_step.dart';
import '../../widgets/profile/new_business/new_business_identity_step.dart';
import '../../widgets/profile/new_business/new_business_intent_view.dart';
import '../../widgets/profile/new_business/new_business_paths_panel.dart';
import '../../widgets/profile/new_business/new_business_review_step.dart';
import '../../widgets/profile/new_business/new_business_wizard_chrome.dart';

enum _NewBusinessPhase { intent, wizard }

class NewBusinessPage extends StatefulWidget {
  final CalendarController calendarController;

  /// Optional deep-link: `create` | `backup` | `legacy`
  final String? initialFlow;

  const NewBusinessPage({
    super.key,
    required this.calendarController,
    this.initialFlow,
  });

  @override
  State<NewBusinessPage> createState() => _NewBusinessPageState();
}

class _NewBusinessPageState extends State<NewBusinessPage> {
  static const int _lastWizardStep = 2;

  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _fiscalTitleController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  BusinessData _businessData = BusinessData();
  _NewBusinessPhase _phase = _NewBusinessPhase.intent;
  int _currentStep = 0;
  bool _isLoading = false;
  bool _showNameError = false;
  bool _legacyWizardOpen = false;
  LegacyApiImportPublicConfig _legacyImportConfig =
      const LegacyApiImportPublicConfig();
  List<Map<String, dynamic>> _currencies = [];
  String? _importJobId;
  int _importProgress = 0;
  String? _importMessage;

  @override
  void initState() {
    super.initState();
    widget.calendarController.addListener(_onCalendarChanged);
    _businessData.businessType ??= BusinessType.shop;
    _businessData.businessField ??= BusinessField.commercial;
    _ensureFiscalDefaults();
    _loadCurrencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrapInitialFlow();
    });
  }

  Future<void> _bootstrapInitialFlow() async {
    final cfg = await LegacyApiImportPublicConfig.fetch(ApiClient());
    if (!mounted) return;
    setState(() => _legacyImportConfig = cfg);
    _applyInitialFlow(widget.initialFlow);
  }

  void _applyInitialFlow(String? flow) {
    switch ((flow ?? '').trim().toLowerCase()) {
      case 'create':
        _startManualWizard();
        break;
      case 'backup':
        _importFromBackup();
        break;
      case 'legacy':
        _openLegacyImport();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _pageController.dispose();
    _nameController.dispose();
    _fiscalTitleController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _onCalendarChanged() {
    if (_businessData.fiscalYears.isEmpty) return;
    final fiscal = _businessData.fiscalYears.first;
    if (fiscal.endDate == null) return;
    if (_isAutoFiscalTitle(fiscal.title)) {
      setState(() {
        fiscal.title = _fiscalAutoTitle(fiscal.endDate!);
        _fiscalTitleController.text = fiscal.title;
      });
    }
  }

  String _fiscalAutoTitle(DateTime end) {
    final t = AppLocalizations.of(context);
    final endStr = HesabixDateUtils.formatForDisplay(
      end,
      widget.calendarController.isJalali,
    );
    return t.fiscalYearEndingTitle(endStr);
  }

  bool _isAutoFiscalTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return true;
    // Localized auto titles always include a date with `/`.
    // Also treat legacy Persian prefix as auto.
    return trimmed.contains('/') &&
        (trimmed.startsWith('سال مالی منتهی به') ||
            trimmed.toLowerCase().startsWith('fiscal year ending'));
  }

  void _ensureFiscalDefaults() {
    if (_businessData.fiscalYears.isEmpty) {
      _businessData.fiscalYears.add(FiscalYearData(isLast: true));
    }
    final fiscal = _businessData.fiscalYears.first;
    if (fiscal.startDate != null) return;

    final DateTime start;
    if (widget.calendarController.isJalali) {
      final now = Jalali.now();
      start = HesabixDateUtils.toDateOnlyLocal(
        Jalali(now.year, 1, 1).toDateTime(),
      );
    } else {
      final now = DateTime.now();
      start = HesabixDateUtils.toDateOnlyLocal(DateTime(now.year, 1, 1));
    }
    fiscal.startDate = start;
    fiscal.endDate = HesabixDateUtils.fiscalYearInclusiveEndFromStart(
      start,
      widget.calendarController.isJalali,
    );
  }

  void _syncFiscalTitleController() {
    if (_businessData.fiscalYears.isEmpty) return;
    final fiscal = _businessData.fiscalYears.first;
    if (fiscal.endDate != null &&
        (fiscal.title.trim().isEmpty || _isAutoFiscalTitle(fiscal.title))) {
      fiscal.title = _fiscalAutoTitle(fiscal.endDate!);
    }
    if (_fiscalTitleController.text != fiscal.title) {
      _fiscalTitleController.text = fiscal.title;
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await BusinessApiService.getCurrencies();
      if (!mounted) return;
      setState(() {
        _currencies = list;
        Map<String, dynamic>? irr;
        for (final e in _currencies) {
          if ((e['code'] as String?) == 'IRR') {
            irr = e;
            break;
          }
        }
        if (irr != null) {
          _businessData.defaultCurrencyId ??= irr['id'] as int?;
          final id = _businessData.defaultCurrencyId;
          if (id != null && !_businessData.currencyIds.contains(id)) {
            _businessData.currencyIds.add(id);
          }
        } else if (_businessData.defaultCurrencyId == null &&
            _currencies.isNotEmpty) {
          final id = _currencies.first['id'] as int?;
          _businessData.defaultCurrencyId = id;
          if (id != null && !_businessData.currencyIds.contains(id)) {
            _businessData.currencyIds.add(id);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  void _startManualWizard() {
    _ensureFiscalDefaults();
    _syncFiscalTitleController();
    setState(() {
      _phase = _NewBusinessPhase.wizard;
      _currentStep = 0;
      _showNameError = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (mounted) {
        _nameFocusNode.requestFocus();
      }
    });
  }

  void _backToIntent() {
    setState(() {
      _phase = _NewBusinessPhase.intent;
      _currentStep = 0;
      _showNameError = false;
    });
  }

  Future<void> _openLegacyImport() async {
    if (_isLoading || _legacyWizardOpen) return;
    if (!_legacyImportConfig.enabledForUsers) {
      final t = AppLocalizations.of(context);
      final msg = _legacyImportConfig.disabledMessage.trim().isNotEmpty
          ? _legacyImportConfig.disabledMessage
          : t.legacyApiImportUnavailableBody;
      SnackBarHelper.showError(context, message: msg);
      return;
    }
    setState(() {
      _legacyWizardOpen = true;
      _isLoading = true;
    });
    try {
      await LegacyImportWizard.show(context);
    } finally {
      if (mounted) {
        setState(() {
          _legacyWizardOpen = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _importFromBackup() async {
    final t = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['hbx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;

      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        SnackBarHelper.showError(context, message: t.importBackupEmptyFile);
        return;
      }

      final filename = file.name;
      final fileExt = filename.toLowerCase().split('.').last;
      if (fileExt == 'hs60') {
        SnackBarHelper.showError(
          context,
          message: t.importBackupHs60Unsupported,
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
        final importResult = await BusinessApiService.importBusinessFromBackup(
          filename: filename,
          fileBytes: file.bytes!,
          asyncMode: true,
        );
        if (!mounted) return;

        final jobId = importResult['job_id'] as String?;
        if (jobId != null) {
          setState(() {
            _importJobId = jobId;
            _importMessage = t.importBackupProcessing;
          });
          await _pollImportJob(jobId);
        } else {
          final businessId = importResult['business_id'] as int?;
          if (businessId != null) {
            SnackBarHelper.showSuccess(context, message: t.importBackupSuccess);
            context.goNamed('profile_businesses');
          }
        }
      } on DioException catch (e) {
        if (!mounted) return;
        String errorMessage = t.importBackupFailed;
        if (e.response?.data != null) {
          final errorData = e.response!.data;
          if (errorData is Map) {
            final error = errorData['error'];
            if (error is Map) {
              errorMessage = error['message']?.toString() ?? errorMessage;
            } else if (errorData['message'] != null) {
              errorMessage = errorData['message'].toString();
            }
          }
        }
        SnackBarHelper.showError(context, message: errorMessage);
      } catch (e) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message:
              '${t.importBackupFailed}: ${ErrorExtractor.forContext(e, context)}',
        );
      } finally {
        if (mounted && _importJobId == null) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${t.importBackupSelectFailed}: ${ErrorExtractor.forContext(e, context)}',
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollImportJob(String jobId) async {
    final t = AppLocalizations.of(context);
    final jobService = JobService();
    try {
      final poll = await jobService.pollUntilComplete(
        jobId,
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _importProgress = progress;
            if (message != null && message.isNotEmpty) {
              _importMessage = message;
            }
          });
        },
      );

      if (!mounted) return;

      if (poll.isSuccess) {
        final businessId = poll.result?['business_id'];
        final stats = poll.result?['stats'];
        final skipped = stats is Map ? stats['documents_skipped'] : null;
        final msg = skipped != null && (skipped as num) > 0
            ? t.importBackupPartialSuccess(skipped.toInt())
            : t.importBackupSuccess;
        SnackBarHelper.showSuccess(context, message: msg);
        if (businessId != null) {
          context.goNamed('profile_businesses');
        }
      } else {
        SnackBarHelper.showError(
          context,
          message: poll.errorMessage ?? t.importBackupFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message:
              '${t.importBackupStatusFailed}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _importJobId = null;
          _isLoading = false;
          _importMessage = null;
        });
      }
    }
  }

  bool _canGoToNextStep() {
    switch (_currentStep) {
      case 0:
        return _businessData.isStep1Valid() &&
            _businessData.isStep2Valid() &&
            _businessData.isStep3Valid();
      case 1:
        return _businessData.isFiscalStepValid() &&
            _businessData.isCurrencyStepValid();
      default:
        return false;
    }
  }

  void _nextStep() {
    _businessData.name = _nameController.text.trim();
    if (!_canGoToNextStep()) {
      if (_currentStep == 0) {
        setState(() => _showNameError = _businessData.name.trim().isEmpty);
      }
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.pleaseFillRequiredFields);
      return;
    }
    if (_currentStep >= _lastWizardStep) return;
    if (_currentStep == 0) {
      _ensureFiscalDefaults();
      _syncFiscalTitleController();
    }
    setState(() {
      _currentStep++;
      _showNameError = false;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _previousStep() {
    if (_currentStep <= 0) {
      _backToIntent();
      return;
    }
    setState(() => _currentStep--);
    _pageController.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToStep(int step) {
    if (step < 0 || step > _lastWizardStep) return;
    if (step > _currentStep) {
      // Only allow forward jump when all intermediate steps are valid.
      for (var i = _currentStep; i < step; i++) {
        final ok = switch (i) {
          0 =>
            _businessData.isStep1Valid() &&
                _businessData.isStep2Valid() &&
                _businessData.isStep3Valid(),
          1 =>
            _businessData.isFiscalStepValid() &&
                _businessData.isCurrencyStepValid(),
          _ => true,
        };
        if (!ok) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showError(
            context,
            message: t.pleaseFillRequiredFields,
          );
          if (i == 0) {
            setState(() => _showNameError = _businessData.name.trim().isEmpty);
          }
          return;
        }
      }
    }
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showVerificationRequiredDialog(String message) async {
    final t = AppLocalizations.of(context);
    final result = await showGlassDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Theme.of(ctx).colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(child: Text(t.verificationRequiredTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Text(
              t.verificationRequiredBody,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.verificationLater),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.verified_user),
            label: Text(t.verificationGo),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      context.go('/user/profile/verification');
    }
  }

  Future<void> _submitBusiness() async {
    final t = AppLocalizations.of(context);
    _businessData.name = _nameController.text.trim();
    if (!_businessData.isFormValid()) {
      SnackBarHelper.showError(context, message: t.pleaseFillRequiredFields);
      if (!_businessData.isStep1Valid() ||
          !_businessData.isStep2Valid() ||
          !_businessData.isStep3Valid()) {
        _goToStep(0);
      } else if (!_businessData.isCurrencyStepValid() ||
          !_businessData.isFiscalStepValid()) {
        _goToStep(1);
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final created = await BusinessApiService.createBusiness(_businessData);
      if (!mounted) return;
      final seedFailed =
          _businessData.includeSampleData &&
          created.sampleDataSeeded == false &&
          (created.sampleDataError != null &&
              created.sampleDataError!.isNotEmpty);
      if (seedFailed) {
        SnackBarHelper.showError(
          context,
          message: '${t.sampleDataSeedWarning}: ${created.sampleDataError}',
        );
      } else {
        SnackBarHelper.showSuccess(
          context,
          message: t.businessCreatedSuccessfully,
        );
      }
      context.goNamed('profile_businesses');
    } on DioException catch (e) {
      if (!mounted) return;

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
        await _showVerificationRequiredDialog(
          errorMessage ?? t.businessCreationFailed,
        );
        return;
      }

      SnackBarHelper.showError(
        context,
        message:
            errorMessage ??
            '${t.businessCreationFailed}: ${ErrorExtractor.forContext(e, context)}',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${t.businessCreationFailed}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> _stepTitles(AppLocalizations t) => [
    t.newBusinessIdentityStepTitle,
    t.newBusinessFinancialStepTitle,
    t.newBusinessReviewStepTitle,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final showWizard = _phase == _NewBusinessPhase.wizard;

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: Text(t.newBusiness),
              centerTitle: true,
              elevation: 0,
              leading: showWizard
                  ? IconButton(
                      tooltip: t.newBusinessBackToOptions,
                      onPressed: _isLoading ? null : _backToIntent,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            )
          : null,
      body: NewBusinessAmbientBackground(
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: showWizard
                  ? KeyedSubtree(
                      key: const ValueKey('wizard'),
                      child: _buildWizard(context, t, isDesktop),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('intent'),
                      child: SingleChildScrollView(
                        child: NewBusinessIntentView(
                          isLoading: _isLoading,
                          onCreateManually: _startManualWizard,
                          onImportBackup: _importFromBackup,
                          onImportLegacy: _openLegacyImport,
                          showLegacyImport: _legacyImportConfig.enabledForUsers,
                        ),
                      ),
                    ),
            ),
            if (_isLoading && _importJobId != null) _buildImportOverlay(t),
          ],
        ),
      ),
    );
  }

  Widget _buildWizard(
    BuildContext context,
    AppLocalizations t,
    bool isDesktop,
  ) {
    final titles = _stepTitles(t);
    final content = Column(
      children: [
        NewBusinessWizardProgress(
          currentStep: _currentStep,
          totalSteps: _lastWizardStep + 1,
          stepTitles: titles,
          onStepTap: _isLoading ? null : _goToStep,
        ),
        Expanded(
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: NewBusinessLivePreview(
                            data: _businessData,
                            currencies: _currencies,
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Expanded(child: _buildPageView()),
                  ],
                )
              : _buildPageView(),
        ),
        NewBusinessWizardNavBar(
          currentStep: _currentStep,
          lastStep: _lastWizardStep,
          canGoNext: _canGoToNextStep(),
          isLoading: _isLoading,
          showBackToOptions: true,
          onBack: _isLoading ? null : _previousStep,
          onNext: _isLoading ? null : _nextStep,
          onSubmit: _isLoading ? null : _submitBusiness,
          onBackToOptions: _isLoading ? null : _backToIntent,
        ),
      ],
    );

    return content;
  }

  Widget _buildPageView() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        setState(() => _currentStep = index);
      },
      children: [
        SingleChildScrollView(
          child: NewBusinessIdentityStep(
            data: _businessData,
            nameController: _nameController,
            nameFocusNode: _nameFocusNode,
            showNameError: _showNameError,
            onChanged: (data) {
              setState(() {
                _businessData = data;
                _showNameError = false;
              });
            },
          ),
        ),
        SingleChildScrollView(
          child: NewBusinessFinancialStep(
            data: _businessData,
            currencies: _currencies,
            calendarController: widget.calendarController,
            fiscalTitleController: _fiscalTitleController,
            fiscalAutoTitle: _fiscalAutoTitle,
            isAutoFiscalTitle: _isAutoFiscalTitle,
            onChanged: (data) => setState(() => _businessData = data),
          ),
        ),
        SingleChildScrollView(
          child: NewBusinessReviewStep(
            data: _businessData,
            currencies: _currencies,
            calendarController: widget.calendarController,
            onEditStep: _goToStep,
          ),
        ),
      ],
    );
  }

  Widget _buildImportOverlay(AppLocalizations t) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.45),
          dismissible: false,
        ),
        Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      value: _importProgress > 0 ? _importProgress / 100 : null,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _importMessage ?? t.importBackupInProgress,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$_importProgress%'),
                  const SizedBox(height: 8),
                  Text(
                    t.importBackupPleaseWait,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
