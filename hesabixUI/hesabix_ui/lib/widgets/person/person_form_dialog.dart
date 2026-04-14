import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../services/credit_api_service.dart';
import '../../utils/number_normalizer.dart';
import '../../services/business_dashboard_service.dart';
import '../../models/business_dashboard_models.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

class PersonFormDialog extends StatefulWidget {
  final int businessId;
  final Person? person; // null برای افزودن، مقدار برای ویرایش
  final VoidCallback? onSuccess;
  final String? initialAliasName; // مقدار اولیه برای نام مستعار

  const PersonFormDialog({
    super.key,
    required this.businessId,
    this.person,
    this.onSuccess,
    this.initialAliasName,
  });

  @override
  State<PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<PersonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _personService = PersonService();
  final _businessDashboardService = BusinessDashboardService(ApiClient());
  bool _isLoading = false;

  // Code (unique) controls
  final _codeController = TextEditingController();
  bool _autoGenerateCode = true;

  // Controllers for basic info
  final _aliasNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _paymentIdController = TextEditingController();

  // Controllers for economic info
  final _nationalIdController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _economicIdController = TextEditingController();

  // Controllers for contact info
  final _countryController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _faxController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _shareCountController = TextEditingController();
  // Commission controllers & state
  final _commissionSalePercentController = TextEditingController();
  final _commissionSalesReturnPercentController = TextEditingController();
  final _commissionSalesAmountController = TextEditingController();
  final _commissionSalesReturnAmountController = TextEditingController();
  bool _commissionExcludeDiscounts = false;
  bool _commissionExcludeAdditionsDeductions = false;
  bool _commissionPostInInvoiceDocument = false;

  // ignore: unused_field
  PersonType _selectedPersonType = PersonType.customer; // legacy single select (for compatibility)
  final Set<PersonType> _selectedPersonTypes = <PersonType>{};
  bool _isActive = true;

  // Bank accounts
  List<PersonBankAccount> _bankAccounts = [];

  // Credit override UI state
  final _creditLimitController = TextEditingController();
  String _creditCheckMode = 'inherit'; // inherit | enabled | disabled
  String? _creditCurrencyLabel;

  late final VoidCallback _aliasAndNameFieldsListener;

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _aliasAndNameFieldsListener = () {
      if (mounted) setState(() {});
    };
    _aliasNameController.addListener(_aliasAndNameFieldsListener);
    _firstNameController.addListener(_aliasAndNameFieldsListener);
    _lastNameController.addListener(_aliasAndNameFieldsListener);
    _loadBusinessCurrencyLabel();
  }

  void _initializeForm() {
    if (widget.person != null) {
      final person = widget.person!;
      if (person.code != null) {
        _codeController.text = person.code!.toString();
        _autoGenerateCode = false;
      }
      _aliasNameController.text = person.aliasName;
      _firstNameController.text = person.firstName ?? '';
      _lastNameController.text = person.lastName ?? '';
      _companyNameController.text = person.companyName ?? '';
      _paymentIdController.text = person.paymentId ?? '';
      _nationalIdController.text = person.nationalId ?? '';
      _registrationNumberController.text = person.registrationNumber ?? '';
      _economicIdController.text = person.economicId ?? '';
      _countryController.text = person.country ?? '';
      _provinceController.text = person.province ?? '';
      _cityController.text = person.city ?? '';
      _addressController.text = person.address ?? '';
      _postalCodeController.text = person.postalCode ?? '';
      _phoneController.text = person.phone ?? '';
      _mobileController.text = person.mobile ?? '';
      _faxController.text = person.fax ?? '';
      _emailController.text = person.email ?? '';
      _websiteController.text = person.website ?? '';
      _selectedPersonType = person.personTypes.isNotEmpty ? person.personTypes.first : PersonType.customer;
      _selectedPersonTypes
        ..clear()
        ..addAll(person.personTypes);
      _isActive = person.isActive;
      _bankAccounts = List.from(person.bankAccounts);
      // مقدار اولیه سهام
      if (person.personTypes.contains(PersonType.shareholder) && person.shareCount != null) {
        _shareCountController.text = person.shareCount!.toString();
      }
      // مقدار اولیه پورسانت
      if (person.commissionSalePercent != null) {
        _commissionSalePercentController.text = person.commissionSalePercent!.toString();
      }
      if (person.commissionSalesReturnPercent != null) {
        _commissionSalesReturnPercentController.text = person.commissionSalesReturnPercent!.toString();
      }
      if (person.commissionSalesAmount != null) {
        _commissionSalesAmountController.text = person.commissionSalesAmount!.toString();
      }
      if (person.commissionSalesReturnAmount != null) {
        _commissionSalesReturnAmountController.text = person.commissionSalesReturnAmount!.toString();
      }
      _commissionExcludeDiscounts = person.commissionExcludeDiscounts;
      _commissionExcludeAdditionsDeductions = person.commissionExcludeAdditionsDeductions;
      _commissionPostInInvoiceDocument = person.commissionPostInInvoiceDocument;
    } else {
      // برای افزودن شخص جدید، نوع شخص به صورت پیش‌فرض "مشتری" انتخاب می‌شود
      _selectedPersonTypes.add(PersonType.customer);
      _selectedPersonType = PersonType.customer;
      
      if (widget.initialAliasName != null && widget.initialAliasName!.isNotEmpty) {
        // اگر مقدار اولیه برای نام مستعار داریم
        _aliasNameController.text = widget.initialAliasName!;
      }
    }
    // Load person credit override if editing
    if (widget.person?.id != null) {
      Future.microtask(() async {
        try {
          final data = await CreditApiService.getPersonCredit(widget.businessId, widget.person!.id!);
          final cl = data['credit_limit'];
          final cce = data['credit_check_enabled'];
          setState(() {
            _creditLimitController.text = cl == null ? '' : (cl as num).toString();
            if (cce == null) {
              _creditCheckMode = 'inherit';
            } else {
              _creditCheckMode = (cce == true) ? 'enabled' : 'disabled';
            }
          });
        } catch (_) {}
      });
    }
  }

  Future<void> _loadBusinessCurrencyLabel() async {
    try {
      final business = await _businessDashboardService.getBusinessWithPermissions(widget.businessId);
      if (!mounted) return;
      final currency = business.defaultCurrency ?? (business.currencies.isNotEmpty ? business.currencies.first : null);
      if (currency == null) return;
      setState(() {
        _creditCurrencyLabel = _formatCurrencyLabel(currency);
      });
    } catch (_) {
      // Silent fail - fallback to localization default
    }
  }

  String _formatCurrencyLabel(CurrencyLite currency) {
    final symbol = currency.symbol.trim();
    if (symbol.isNotEmpty) return symbol;
    final title = currency.title.trim();
    final code = currency.code.trim();
    if (title.isNotEmpty && code.isNotEmpty) {
      return '$title ($code)';
    }
    if (title.isNotEmpty) return title;
    if (code.isNotEmpty) return code;
    return '';
  }

  @override
  void dispose() {
    _aliasNameController.removeListener(_aliasAndNameFieldsListener);
    _firstNameController.removeListener(_aliasAndNameFieldsListener);
    _lastNameController.removeListener(_aliasAndNameFieldsListener);
    _codeController.dispose();
    _aliasNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyNameController.dispose();
    _paymentIdController.dispose();
    _nationalIdController.dispose();
    _registrationNumberController.dispose();
    _economicIdController.dispose();
    _countryController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _faxController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _shareCountController.dispose();
    _commissionSalePercentController.dispose();
    _commissionSalesReturnPercentController.dispose();
    _commissionSalesAmountController.dispose();
    _commissionSalesReturnAmountController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _savePerson() async {
    final t = AppLocalizations.of(context);

    // حداقل یک نوع شخص باید انتخاب شود
    if (_selectedPersonTypes.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.personTypeRequired,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    Person? resultPerson;
    try {
      if (widget.person == null) {
        // Create new person
        final personData = PersonCreateRequest(
          code: _autoGenerateCode
              ? null
              : (int.tryParse(_codeController.text.trim())),
          aliasName: _aliasNameController.text.trim(),
          firstName: _firstNameController.text.trim().isEmpty ? null : _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty ? null : _lastNameController.text.trim(),
          personTypes: _selectedPersonTypes.toList(),
          companyName: _companyNameController.text.trim().isEmpty ? null : _companyNameController.text.trim(),
          paymentId: _paymentIdController.text.trim().isEmpty ? null : _paymentIdController.text.trim(),
          nationalId: _nationalIdController.text.trim().isEmpty ? null : _nationalIdController.text.trim(),
          registrationNumber: _registrationNumberController.text.trim().isEmpty ? null : _registrationNumberController.text.trim(),
          economicId: _economicIdController.text.trim().isEmpty ? null : _economicIdController.text.trim(),
          country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
          province: _provinceController.text.trim().isEmpty ? null : _provinceController.text.trim(),
          city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty ? null : _postalCodeController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
          fax: _faxController.text.trim().isEmpty ? null : _faxController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
          bankAccounts: _bankAccounts,
          shareCount: _selectedPersonTypes.contains(PersonType.shareholder)
              ? int.tryParse(_shareCountController.text.trim())
              : null,
          // commission fields only if marketer or seller
          commissionSalePercent: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalePercentController.text.trim())
              : null,
          commissionSalesReturnPercent: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesReturnPercentController.text.trim())
              : null,
          commissionSalesAmount: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesAmountController.text.trim())
              : null,
          commissionSalesReturnAmount: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesReturnAmountController.text.trim())
              : null,
          commissionExcludeDiscounts: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionExcludeDiscounts
              : null,
          commissionExcludeAdditionsDeductions: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionExcludeAdditionsDeductions
              : null,
          commissionPostInInvoiceDocument: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionPostInInvoiceDocument
              : null,
        );

        final created = await _personService.createPerson(
          businessId: widget.businessId,
          personData: personData,
        );
        // Update credit override if any
        final double? creditLimit = _creditLimitController.text.trim().isEmpty ? null : double.tryParse(_creditLimitController.text.trim());
        bool? creditCheckEnabled;
        if (_creditCheckMode == 'inherit') {
          creditCheckEnabled = null;
        } else if (_creditCheckMode == 'enabled') {
          creditCheckEnabled = true;
        } else {
          creditCheckEnabled = false;
        }
        if (creditLimit != null || creditCheckEnabled != null) {
          await CreditApiService.updatePersonCredit(widget.businessId, created.id!, creditLimit: creditLimit, creditCheckEnabled: creditCheckEnabled);
        }
        resultPerson = created;
      } else {
        // Update existing person
        final personData = PersonUpdateRequest(
          code: (int.tryParse(_codeController.text.trim())),
          aliasName: _aliasNameController.text.trim(),
          firstName: _firstNameController.text.trim().isEmpty ? null : _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty ? null : _lastNameController.text.trim(),
          personTypes: _selectedPersonTypes.isNotEmpty ? _selectedPersonTypes.toList() : null,
          companyName: _companyNameController.text.trim().isEmpty ? null : _companyNameController.text.trim(),
          paymentId: _paymentIdController.text.trim().isEmpty ? null : _paymentIdController.text.trim(),
          nationalId: _nationalIdController.text.trim().isEmpty ? null : _nationalIdController.text.trim(),
          registrationNumber: _registrationNumberController.text.trim().isEmpty ? null : _registrationNumberController.text.trim(),
          economicId: _economicIdController.text.trim().isEmpty ? null : _economicIdController.text.trim(),
          country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
          province: _provinceController.text.trim().isEmpty ? null : _provinceController.text.trim(),
          city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty ? null : _postalCodeController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
          fax: _faxController.text.trim().isEmpty ? null : _faxController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
          isActive: _isActive,
          shareCount: _selectedPersonTypes.contains(PersonType.shareholder)
              ? int.tryParse(_shareCountController.text.trim())
              : null,
          commissionSalePercent: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalePercentController.text.trim())
              : null,
          commissionSalesReturnPercent: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesReturnPercentController.text.trim())
              : null,
          commissionSalesAmount: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesAmountController.text.trim())
              : null,
          commissionSalesReturnAmount: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? double.tryParse(_commissionSalesReturnAmountController.text.trim())
              : null,
          commissionExcludeDiscounts: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionExcludeDiscounts
              : null,
          commissionExcludeAdditionsDeductions: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionExcludeAdditionsDeductions
              : null,
          commissionPostInInvoiceDocument: (_selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller))
              ? _commissionPostInInvoiceDocument
              : null,
        );

        final updated = await _personService.updatePerson(
          personId: widget.person!.id!,
          personData: personData,
        );
        // Update credit override if any
        final double? creditLimit = _creditLimitController.text.trim().isEmpty ? null : double.tryParse(_creditLimitController.text.trim());
        bool? creditCheckEnabled;
        if (_creditCheckMode == 'inherit') {
          creditCheckEnabled = null;
        } else if (_creditCheckMode == 'enabled') {
          creditCheckEnabled = true;
        } else {
          creditCheckEnabled = false;
        }
        if (creditLimit != null || creditCheckEnabled != null) {
          await CreditApiService.updatePersonCredit(widget.businessId, updated.id!, creditLimit: creditLimit, creditCheckEnabled: creditCheckEnabled);
        }
        resultPerson = updated;
      }

      if (mounted) {
        widget.onSuccess?.call();
        Navigator.of(context).pop(resultPerson);
        SnackBarHelper.showSuccess(
          context,
          message: widget.person == null 
            ? AppLocalizations.of(context).personCreatedSuccessfully
            : AppLocalizations.of(context).personUpdatedSuccessfully,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addBankAccount() {
    setState(() {
      _bankAccounts.add(PersonBankAccount(
        personId: 0, // Will be set when person is created
        bankName: '',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    });
  }

  void _removeBankAccount(int index) {
    setState(() {
      _bankAccounts.removeAt(index);
    });
  }

  void _updateBankAccount(int index, PersonBankAccount bankAccount) {
    setState(() {
      _bankAccounts[index] = bankAccount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEditing = widget.person != null;
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final dialogConstraints = ResponsiveHelper.getDialogConstraints(context);

    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      child: Container(
        constraints: dialogConstraints,
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            if (isMobile)
              AppBar(
                title: Text(isEditing ? t.editPerson : t.addPerson),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                automaticallyImplyLeading: false,
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isEditing ? Icons.edit : Icons.add,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditing ? t.editPerson : t.addPerson,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
              ),
            SizedBox(height: isMobile ? 8 : 16),

            // Form with tabs
            Expanded(
              child: Form(
                key: _formKey,
                child: Builder(builder: (context) {
                  final hasCommissionTab = _selectedPersonTypes.contains(PersonType.marketer) || _selectedPersonTypes.contains(PersonType.seller);
                  final tabs = <Tab>[
                    Tab(text: t.personBasicInfo),
                    Tab(text: t.personEconomicInfo),
                    Tab(text: t.personContactInfo),
                    Tab(text: t.personBankInfo),
                    Tab(text: t.creditTabTitle),
                  ];
                  final views = <Widget>[
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                        child: _buildBasicInfoFields(t, isMobile),
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                        child: _buildEconomicInfoFields(t, isMobile),
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                        child: _buildContactInfoFields(t, isMobile),
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                        child: _buildBankAccountsSection(t, isMobile),
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                        child: _buildCreditOverrideSection(),
                      ),
                    ),
                  ];
                  if (hasCommissionTab) {
                    tabs.add(Tab(text: t.commissionSalePercentLabel));
                    views.add(
                      SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
                          child: _buildCommissionTab(isMobile),
                        ),
                      ),
                    );
                  }
                  return DefaultTabController(
                    key: ValueKey(tabs.length),
                    length: tabs.length,
                    child: Column(
                      children: [
                        TabBar(
                          isScrollable: isMobile,
                          tabs: tabs,
                        ),
                        SizedBox(height: isMobile ? 8 : 12),
                        Expanded(
                          child: TabBarView(children: views),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),

            // Actions
            const Divider(),
            SizedBox(height: isMobile ? 8 : 16),
            if (isMobile)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _savePerson,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEditing ? t.update : t.add),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: Text(t.cancel),
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _savePerson,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEditing ? t.update : t.add),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionTab(bool isMobile) {
    final t = AppLocalizations.of(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    final isMarketer = _selectedPersonTypes.contains(PersonType.marketer);
    final isSeller = _selectedPersonTypes.contains(PersonType.seller);
    if (!isMarketer && !isSeller) {
      return Center(
        child: Text(t.onlyForMarketerSeller),
      );
    }

    return Column(
      children: [
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _commissionSalePercentController,
                decoration: InputDecoration(
                  labelText: t.percentFromSales,
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if ((isMarketer || isSeller) && (v != null && v.isNotEmpty)) {
                    final num? val = num.tryParse(v);
                    if (val == null || val < 0 || val > 100) return t.mustBeBetweenZeroAndHundred;
                  }
                  return null;
                },
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _commissionSalesReturnPercentController,
                decoration: InputDecoration(
                  labelText: t.percentFromSalesReturn,
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if ((isMarketer || isSeller) && (v != null && v.isNotEmpty)) {
                    final num? val = num.tryParse(v);
                    if (val == null || val < 0 || val > 100) return t.mustBeBetweenZeroAndHundred;
                  }
                  return null;
                },
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _commissionSalePercentController,
                  decoration: InputDecoration(
                    labelText: t.percentFromSales,
                    suffixText: '%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if ((isMarketer || isSeller) && (v != null && v.isNotEmpty)) {
                      final num? val = num.tryParse(v);
                      if (val == null || val < 0 || val > 100) return t.mustBeBetweenZeroAndHundred;
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _commissionSalesReturnPercentController,
                  decoration: InputDecoration(
                    labelText: t.percentFromSalesReturn,
                    suffixText: '%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if ((isMarketer || isSeller) && (v != null && v.isNotEmpty)) {
                      final num? val = num.tryParse(v);
                      if (val == null || val < 0 || val > 100) return t.mustBeBetweenZeroAndHundred;
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _commissionSalesAmountController,
                decoration: InputDecoration(
                  labelText: t.salesAmount,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final num? val = num.tryParse(v);
                    if (val == null || val < 0) return t.mustBePositiveNumber;
                  }
                  return null;
                },
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _commissionSalesReturnAmountController,
                decoration: InputDecoration(
                  labelText: t.salesReturnAmount,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final num? val = num.tryParse(v);
                    if (val == null || val < 0) return t.mustBePositiveNumber;
                  }
                  return null;
                },
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _commissionSalesAmountController,
                  decoration: InputDecoration(
                    labelText: t.salesAmount,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      final num? val = num.tryParse(v);
                      if (val == null || val < 0) return t.mustBePositiveNumber;
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _commissionSalesReturnAmountController,
                  decoration: InputDecoration(
                    labelText: t.salesReturnAmount,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      final num? val = num.tryParse(v);
                      if (val == null || val < 0) return t.mustBePositiveNumber;
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              SwitchListTile(
                title: Text(t.commissionExcludeDiscounts),
                value: _commissionExcludeDiscounts,
                onChanged: (v) { setState(() { _commissionExcludeDiscounts = v; }); },
              ),
              SwitchListTile(
                title: Text(t.commissionExcludeAdditionsDeductions),
                value: _commissionExcludeAdditionsDeductions,
                onChanged: (v) { setState(() { _commissionExcludeAdditionsDeductions = v; }); },
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  title: Text(t.commissionExcludeDiscounts),
                  value: _commissionExcludeDiscounts,
                  onChanged: (v) { setState(() { _commissionExcludeDiscounts = v; }); },
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: SwitchListTile(
                  title: Text(t.commissionExcludeAdditionsDeductions),
                  value: _commissionExcludeAdditionsDeductions,
                  onChanged: (v) { setState(() { _commissionExcludeAdditionsDeductions = v; }); },
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        SwitchListTile(
          title: Text(t.commissionPostInInvoiceDocument),
          value: _commissionPostInInvoiceDocument,
          onChanged: (v) { setState(() { _commissionPostInInvoiceDocument = v; }); },
        ),
      ],
    );
  }

  Widget _buildCreditOverrideSection() {
    final t = AppLocalizations.of(context);
    return FutureBuilder<String?>(
      future: _getCurrencyLabel(),
      builder: (context, snapshot) {
        final currencyLabel = snapshot.data;
        final labelText = currencyLabel != null 
            ? '${t.creditLimitLabel} ($currencyLabel)'
            : t.creditLimitLabel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.creditPersonPolicyTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _creditCheckMode,
              items: [
                DropdownMenuItem(value: 'inherit', child: Text(t.creditCheckModeInherit)),
                DropdownMenuItem(value: 'enabled', child: Text(t.creditCheckModeEnabled)),
                DropdownMenuItem(value: 'disabled', child: Text(t.creditCheckModeDisabled)),
              ],
              onChanged: (v) => setState(() => _creditCheckMode = v ?? 'inherit'),
              decoration: InputDecoration(labelText: t.creditCheckModeLabel),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _creditLimitController,
              decoration: InputDecoration(
                labelText: labelText,
                hintText: t.creditLimitHint,
                border: const OutlineInputBorder(),
                suffixText: currencyLabel,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.creditTipText),
          ],
        );
      },
    );
  }

  Future<String?> _getCurrencyLabel() async {
    if (_creditCurrencyLabel?.isNotEmpty == true) {
      return _creditCurrencyLabel;
    }
    // Try to load currency label if not already loaded
    try {
      final business = await _businessDashboardService.getBusinessWithPermissions(widget.businessId);
      final currency = business.defaultCurrency ?? (business.currencies.isNotEmpty ? business.currencies.first : null);
      if (currency == null) return null;
      final label = _formatCurrencyLabel(currency);
      if (label.isNotEmpty) {
        setState(() {
          _creditCurrencyLabel = label;
        });
        return label;
      }
    } catch (_) {
      // Silent fail
    }
    return null;
  }

  /// وقتی نام مستعار خالی است، از نام / نام خانوادگی (یا ترکیب هر دو) پیشنهاد برای انتخاب سریع.
  List<String> _aliasNameCombinationOptions() {
    if (_aliasNameController.text.trim().isNotEmpty) return [];
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isEmpty && last.isEmpty) return [];
    if (first.isNotEmpty && last.isEmpty) return [first];
    if (first.isEmpty && last.isNotEmpty) return [last];
    final withSpace = '$first $last';
    final withSpaceReversed = '$last $first';
    final withComma = '$first، $last';
    final seen = <String>{};
    final out = <String>[];
    for (final s in [first, last, withSpace, withSpaceReversed, withComma]) {
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  Widget _buildAliasNameTextField(AppLocalizations t) {
    return TextFormField(
      controller: _aliasNameController,
      decoration: InputDecoration(
        label: RichText(
          text: TextSpan(
            text: t.personAliasName,
            style: Theme.of(context).inputDecorationTheme.labelStyle ??
                Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        hintText: t.personAliasName,
        helperText: t.required,
        helperMaxLines: 1,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return t.personAliasNameRequired;
        }
        return null;
      },
    );
  }

  Widget _buildAliasNameSuggestionCombo(AppLocalizations t) {
    final options = _aliasNameCombinationOptions();
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        hint: Text(
          t.personAliasPickFromNamesHint,
          overflow: TextOverflow.ellipsis,
        ),
        items: options
            .map(
              (s) => DropdownMenuItem<String>(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _aliasNameController.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
          });
        },
      ),
    );
  }

  Widget _buildBasicInfoFields(AppLocalizations t, bool isMobile) {
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      children: [
        TextFormField(
          controller: _codeController,
          readOnly: _autoGenerateCode,
          decoration: InputDecoration(
            labelText: t.personCodeOptional,
            hintText: t.uniqueCodeNumeric,
            suffixIcon: Container(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: ToggleButtons(
                isSelected: [_autoGenerateCode, !_autoGenerateCode],
                borderRadius: BorderRadius.circular(6),
                constraints: const BoxConstraints(minHeight: 32, minWidth: 64),
                onPressed: (index) {
                  setState(() {
                    _autoGenerateCode = (index == 0);
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(t.automatic),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(t.manual),
                  ),
                ],
              ),
            ),
          ),
          inputFormatters: [
            const EnglishDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
          ],
          keyboardType: TextInputType.number,
          validator: (value) {
            if (!_autoGenerateCode) {
              if (value == null || value.trim().isEmpty) {
                return t.personCodeRequired;
              }
              if (int.tryParse(value.trim()) == null) {
                return t.codeMustBeNumeric;
              }
            }
            return null;
          },
        ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAliasNameTextField(t),
              _buildAliasNameSuggestionCombo(t),
              SizedBox(height: spacing),
              _buildPersonTypesMultiSelect(t),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAliasNameTextField(t),
                    _buildAliasNameSuggestionCombo(t),
                  ],
                ),
              ),
              SizedBox(width: spacing),
              Expanded(child: _buildPersonTypesMultiSelect(t)),
            ],
          ),
        SizedBox(height: spacing),
        if (_selectedPersonTypes.contains(PersonType.shareholder))
          TextFormField(
            controller: _shareCountController,
            decoration: InputDecoration(
              labelText: t.shareCount,
              hintText: t.integerNoDecimal,
            ),
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            keyboardType: TextInputType.number,
            validator: (value) {
              if (_selectedPersonTypes.contains(PersonType.shareholder)) {
                if (value == null || value.trim().isEmpty) {
                  return t.shareholderShareCountRequired;
                }
                final parsed = int.tryParse(value.trim());
                if (parsed == null || parsed <= 0) {
                  return 'تعداد سهام باید عدد صحیح بزرگتر از صفر باشد';
                }
              }
              return null;
            },
          ),
        if (_selectedPersonTypes.contains(PersonType.shareholder))
          SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: InputDecoration(
                  labelText: t.personFirstName,
                  hintText: t.personFirstName,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _lastNameController,
                decoration: InputDecoration(
                  labelText: t.personLastName,
                  hintText: t.personLastName,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _companyNameController,
                decoration: InputDecoration(
                  labelText: t.personCompanyName,
                  hintText: t.personCompanyName,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _paymentIdController,
                decoration: InputDecoration(
                  labelText: t.personPaymentId,
                  hintText: t.personPaymentId,
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: t.personFirstName,
                        hintText: t.personFirstName,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: t.personLastName,
                        hintText: t.personLastName,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _companyNameController,
                      decoration: InputDecoration(
                        labelText: t.personCompanyName,
                        hintText: t.personCompanyName,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: TextFormField(
                      controller: _paymentIdController,
                      decoration: InputDecoration(
                        labelText: t.personPaymentId,
                        hintText: t.personPaymentId,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildPersonTypesMultiSelect(AppLocalizations t) {
    final types = PersonType.values;
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: spacing / 2),
          child: Text(t.personType),
        ),
        Wrap(
          spacing: spacing,
          runSpacing: spacing / 2,
          children: types.map((type) {
            final selected = _selectedPersonTypes.contains(type);
            return FilterChip(
              label: Text(_getPersonTypeLabel(type, t)),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedPersonTypes.add(type);
                  } else {
                    _selectedPersonTypes.remove(type);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getPersonTypeLabel(PersonType type, AppLocalizations t) {
    switch (type) {
      case PersonType.customer:
        return t.personTypeCustomer;
      case PersonType.marketer:
        return t.personTypeMarketer;
      case PersonType.employee:
        return t.personTypeEmployee;
      case PersonType.supplier:
        return t.personTypeSupplier;
      case PersonType.partner:
        return t.personTypePartner;
      case PersonType.seller:
        return t.personTypeSeller;
      case PersonType.shareholder:
        return t.personTypeShareholder;
    }
  }

  Widget _buildEconomicInfoFields(AppLocalizations t, bool isMobile) {
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      children: [
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _nationalIdController,
                decoration: InputDecoration(
                  labelText: t.personNationalId,
                  hintText: t.personNationalId,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _registrationNumberController,
                decoration: InputDecoration(
                  labelText: t.personRegistrationNumber,
                  hintText: t.personRegistrationNumber,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _nationalIdController,
                  decoration: InputDecoration(
                    labelText: t.personNationalId,
                    hintText: t.personNationalId,
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _registrationNumberController,
                  decoration: InputDecoration(
                    labelText: t.personRegistrationNumber,
                    hintText: t.personRegistrationNumber,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        TextFormField(
          controller: _economicIdController,
          decoration: InputDecoration(
            labelText: t.personEconomicId,
            hintText: t.personEconomicId,
          ),
        ),
      ],
    );
  }

  Widget _buildContactInfoFields(AppLocalizations t, bool isMobile) {
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      children: [
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _countryController,
                decoration: InputDecoration(
                  labelText: t.personCountry,
                  hintText: t.personCountry,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _provinceController,
                decoration: InputDecoration(
                  labelText: t.personProvince,
                  hintText: t.personProvince,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _countryController,
                  decoration: InputDecoration(
                    labelText: t.personCountry,
                    hintText: t.personCountry,
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _provinceController,
                  decoration: InputDecoration(
                    labelText: t.personProvince,
                    hintText: t.personProvince,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: t.personCity,
                  hintText: t.personCity,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _postalCodeController,
                decoration: InputDecoration(
                  labelText: t.personPostalCode,
                  hintText: t.personPostalCode,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cityController,
                  decoration: InputDecoration(
                    labelText: t.personCity,
                    hintText: t.personCity,
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _postalCodeController,
                  decoration: InputDecoration(
                    labelText: t.personPostalCode,
                    hintText: t.personPostalCode,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            labelText: t.personAddress,
            hintText: t.personAddress,
          ),
          maxLines: 3,
        ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: t.personPhone,
                  hintText: t.personPhone,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _mobileController,
                decoration: InputDecoration(
                  labelText: t.personMobile,
                  hintText: t.personMobile,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: t.personPhone,
                    hintText: t.personPhone,
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _mobileController,
                  decoration: InputDecoration(
                    labelText: t.personMobile,
                    hintText: t.personMobile,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                controller: _faxController,
                decoration: InputDecoration(
                  labelText: t.personFax,
                  hintText: t.personFax,
                ),
              ),
              SizedBox(height: spacing),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: t.personEmail,
                  hintText: t.personEmail,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _faxController,
                  decoration: InputDecoration(
                    labelText: t.personFax,
                    hintText: t.personFax,
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: t.personEmail,
                    hintText: t.personEmail,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
        SizedBox(height: spacing),
        TextFormField(
          controller: _websiteController,
          decoration: InputDecoration(
            labelText: t.personWebsite,
            hintText: t.personWebsite,
          ),
        ),
      ],
    );
  }

  Widget _buildBankAccountsSection(AppLocalizations t, bool isMobile) {
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      children: [
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.personBankAccounts,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addBankAccount,
                icon: const Icon(Icons.add),
                label: Text(t.addBankAccount),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.personBankAccounts,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ElevatedButton.icon(
                onPressed: _addBankAccount,
                icon: const Icon(Icons.add),
                label: Text(t.addBankAccount),
              ),
            ],
          ),
        SizedBox(height: spacing),
        if (_bankAccounts.isEmpty)
          Container(
            padding: EdgeInsets.all(spacing),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(t.noBankAccountsAdded, style: TextStyle(color: Colors.grey.shade600)),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _bankAccounts.length,
            itemBuilder: (context, index) {
              return _buildBankAccountCard(t, index, isMobile);
            },
          ),
      ],
    );
  }

  Widget _buildBankAccountCard(AppLocalizations t, int index, bool isMobile) {
    final bankAccount = _bankAccounts[index];
    final spacing = ResponsiveHelper.getGridSpacing(context);
    
    return Card(
      margin: EdgeInsets.only(bottom: spacing),
      child: Padding(
        padding: EdgeInsets.all(spacing),
        child: Column(
          children: [
            if (isMobile)
              Column(
                children: [
                  TextFormField(
                    initialValue: bankAccount.bankName,
                    decoration: InputDecoration(labelText: t.bankName, hintText: t.bankName),
                    onChanged: (value) {
                      _updateBankAccount(index, bankAccount.copyWith(bankName: value));
                    },
                  ),
                  SizedBox(height: spacing),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => _removeBankAccount(index),
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: bankAccount.bankName,
                      decoration: InputDecoration(labelText: t.bankName, hintText: t.bankName),
                      onChanged: (value) {
                        _updateBankAccount(index, bankAccount.copyWith(bankName: value));
                      },
                    ),
                  ),
                  SizedBox(width: spacing),
                  IconButton(
                    onPressed: () => _removeBankAccount(index),
                    icon: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              ),
            SizedBox(height: spacing),
            if (isMobile)
              Column(
                children: [
                  TextFormField(
                    initialValue: bankAccount.accountNumber ?? '',
                    decoration: InputDecoration(labelText: t.accountNumber, hintText: t.accountNumber),
                    onChanged: (value) {
                      _updateBankAccount(index, bankAccount.copyWith(accountNumber: value.isEmpty ? null : value));
                    },
                  ),
                  SizedBox(height: spacing),
                  TextFormField(
                    initialValue: bankAccount.cardNumber ?? '',
                    decoration: InputDecoration(labelText: t.cardNumber, hintText: t.cardNumber),
                    onChanged: (value) {
                      _updateBankAccount(index, bankAccount.copyWith(cardNumber: value.isEmpty ? null : value));
                    },
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: bankAccount.accountNumber ?? '',
                      decoration: InputDecoration(labelText: t.accountNumber, hintText: t.accountNumber),
                      onChanged: (value) {
                        _updateBankAccount(index, bankAccount.copyWith(accountNumber: value.isEmpty ? null : value));
                      },
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: TextFormField(
                      initialValue: bankAccount.cardNumber ?? '',
                      decoration: InputDecoration(labelText: t.cardNumber, hintText: t.cardNumber),
                      onChanged: (value) {
                        _updateBankAccount(index, bankAccount.copyWith(cardNumber: value.isEmpty ? null : value));
                      },
                    ),
                  ),
                ],
              ),
            SizedBox(height: spacing),
            TextFormField(
              initialValue: bankAccount.shebaNumber ?? '',
              decoration: InputDecoration(labelText: t.shebaNumber, hintText: t.shebaNumber),
              onChanged: (value) {
                _updateBankAccount(index, bankAccount.copyWith(shebaNumber: value.isEmpty ? null : value));
              },
            ),
          ],
        ),
      ),
    );
  }
}
