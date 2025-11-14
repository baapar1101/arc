import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/models/business_models.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/core/api_client.dart';

class BusinessInfoSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessInfoSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessInfoSettingsPage> createState() => _BusinessInfoSettingsPageState();
}

class _BusinessInfoSettingsPageState extends State<BusinessInfoSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  BusinessResponse? _original;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _economicIdController = TextEditingController();
  final _countryController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();

  BusinessType? _businessType;
  BusinessField? _businessField;
  // تنظیمات اعتبار
  bool _checkCreditEnabledByDefault = false;
  final _defaultCreditLimitController = TextEditingController();

  late final ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _postalCodeController.dispose();
    _nationalIdController.dispose();
    _registrationNumberController.dispose();
    _economicIdController.dispose();
    _countryController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _defaultCreditLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await BusinessApiService.getBusiness(widget.businessId);
      _original = resp;
      _nameController.text = resp.name;
      _addressController.text = resp.address ?? '';
      _phoneController.text = resp.phone ?? '';
      _mobileController.text = resp.mobile ?? '';
      _postalCodeController.text = resp.postalCode ?? '';
      _nationalIdController.text = resp.nationalId ?? '';
      _registrationNumberController.text = resp.registrationNumber ?? '';
      _economicIdController.text = resp.economicId ?? '';
      _countryController.text = resp.country ?? '';
      _provinceController.text = resp.province ?? '';
      _cityController.text = resp.city ?? '';
      _businessType = _resolveBusinessType(resp.businessType);
      _businessField = _resolveBusinessField(resp.businessField);
      _checkCreditEnabledByDefault = resp.checkCreditEnabledByDefault;
      _defaultCreditLimitController.text = (resp.defaultCreditLimit ?? 0).toStringAsFixed(0);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  BusinessType? _resolveBusinessType(String value) {
    for (final t in BusinessType.values) {
      if (t.displayName == value) return t;
    }
    return null;
  }

  BusinessField? _resolveBusinessField(String value) {
    for (final f in BusinessField.values) {
      if (f.displayName == value) return f;
    }
    return null;
  }

  Map<String, dynamic> _buildUpdatePayload() {
    final orig = _original!;
    final payload = <String, dynamic>{};

    if (_nameController.text.trim() != orig.name) payload['name'] = _nameController.text.trim();
    if (_businessType != null && _businessType!.displayName != orig.businessType) {
      payload['business_type'] = _businessType!.displayName;
    }
    if (_businessField != null && _businessField!.displayName != orig.businessField) {
      payload['business_field'] = _businessField!.displayName;
    }
    final addr = _addressController.text.trim();
    if ((orig.address ?? '') != addr) payload['address'] = addr.isEmpty ? null : addr;
    final phone = _phoneController.text.trim();
    if ((orig.phone ?? '') != phone) payload['phone'] = phone.isEmpty ? null : phone;
    final mobile = _mobileController.text.trim();
    if ((orig.mobile ?? '') != mobile) payload['mobile'] = mobile.isEmpty ? null : mobile;
    final postal = _postalCodeController.text.trim();
    if ((orig.postalCode ?? '') != postal) payload['postal_code'] = postal.isEmpty ? null : postal;
    final nid = _nationalIdController.text.trim();
    if ((orig.nationalId ?? '') != nid) payload['national_id'] = nid.isEmpty ? null : nid;
    final reg = _registrationNumberController.text.trim();
    if ((orig.registrationNumber ?? '') != reg) payload['registration_number'] = reg.isEmpty ? null : reg;
    final eco = _economicIdController.text.trim();
    if ((orig.economicId ?? '') != eco) payload['economic_id'] = eco.isEmpty ? null : eco;
    final country = _countryController.text.trim();
    if ((orig.country ?? '') != country) payload['country'] = country.isEmpty ? null : country;
    final province = _provinceController.text.trim();
    if ((orig.province ?? '') != province) payload['province'] = province.isEmpty ? null : province;
    final city = _cityController.text.trim();
    if ((orig.city ?? '') != city) payload['city'] = city.isEmpty ? null : city;
    // تنظیمات اعتبار
    final defaultCreditLimitStr = _defaultCreditLimitController.text.trim();
    final parsedLimit = double.tryParse(defaultCreditLimitStr.replaceAll(',', ''));
    if ((orig.defaultCreditLimit ?? 0) != (parsedLimit ?? 0)) {
      payload['default_credit_limit'] = parsedLimit;
    }
    if (orig.checkCreditEnabledByDefault != _checkCreditEnabledByDefault) {
      payload['check_credit_enabled_by_default'] = _checkCreditEnabledByDefault;
    }

    return payload;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_original == null) return;
    final payload = _buildUpdatePayload();
    if (payload.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بدون تغییر')));
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final resp = await _apiClient.put('/api/v1/businesses/${widget.businessId}', data: payload);
      if (resp.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('با موفقیت ذخیره شد')));
          context.go('/business/${widget.businessId}/settings');
        }
      } else {
        throw Exception(resp.data['message'] ?? 'خطا در ذخیره تغییرات');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.businessSettings)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.businessSettings)),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessSettings),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(t.save),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(t.generalSettings, cs),
              const SizedBox(height: 8),
              _buildTextField(controller: _nameController, label: t.businessName, required: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildBusinessTypeDropdown(t)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildBusinessFieldDropdown(t)),
                ],
              ),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessContactInfo, cs),
              const SizedBox(height: 8),
              _buildTextField(controller: _addressController, label: t.address, maxLines: 2),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _phoneController, label: t.phone)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(controller: _mobileController, label: t.mobile)),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _postalCodeController, label: t.postalCode),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessLegalInfo, cs),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _nationalIdController, label: t.nationalId)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(controller: _registrationNumberController, label: t.registrationNumber)),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _economicIdController, label: t.economicId),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessGeographicInfo, cs),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _countryController, label: t.country)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(controller: _provinceController, label: t.province)),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _cityController, label: t.city),
              
              const SizedBox(height: 24),
              _buildSectionTitle('تنظیمات اعتبار مشتریان', cs),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('بررسی اعتبار مشتریان (پیش‌فرض)'),
                subtitle: const Text('در صورت روشن بودن، به‌صورت پیش‌فرض اعتبار مشتریان بررسی می‌شود'),
                value: _checkCreditEnabledByDefault,
                onChanged: (v) => setState(() => _checkCreditEnabledByDefault = v),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _defaultCreditLimitController,
                decoration: const InputDecoration(
                  labelText: 'سقف اعتبار پیش‌فرض (ریال)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (val) {
        if (required && (val == null || val.trim().isEmpty)) {
          return label;
        }
        return null;
      },
    );
  }

  Widget _buildBusinessTypeDropdown(AppLocalizations t) {
    return DropdownButtonFormField<BusinessType>(
      value: _businessType,
      decoration: InputDecoration(labelText: t.businessType),
      items: BusinessType.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _businessType = val),
      validator: (val) => val == null ? t.businessType : null,
    );
  }

  Widget _buildBusinessFieldDropdown(AppLocalizations t) {
    return DropdownButtonFormField<BusinessField>(
      value: _businessField,
      decoration: InputDecoration(labelText: t.businessField),
      items: BusinessField.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _businessField = val),
      validator: (val) => val == null ? t.businessField : null,
    );
  }
}


