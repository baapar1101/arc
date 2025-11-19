import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
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

  // فایل‌های گرافیکی
  Uint8List? _logoBytes;
  Uint8List? _stampBytes;
  bool _uploadingLogo = false;
  bool _uploadingStamp = false;

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

      // بارگذاری پیش‌نمایش لوگو و مهر در صورت وجود
      await _loadBrandingImages(resp);
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

  Future<void> _loadBrandingImages(BusinessResponse resp) async {
    _logoBytes = null;
    _stampBytes = null;
    try {
      if (resp.logoFileId != null && resp.logoFileId!.isNotEmpty) {
        final res = await _apiClient.get<List<int>>(
          '/api/v1/businesses/${widget.businessId}/logo',
          options: dio.Options(responseType: dio.ResponseType.bytes),
        );
        final data = res.data;
        if (data != null && data.isNotEmpty) {
          _logoBytes = Uint8List.fromList(data);
        }
      }
    } catch (_) {
      _logoBytes = null;
    }
    try {
      if (resp.stampFileId != null && resp.stampFileId!.isNotEmpty) {
        final res = await _apiClient.get<List<int>>(
          '/api/v1/businesses/${widget.businessId}/stamp',
          options: dio.Options(responseType: dio.ResponseType.bytes),
        );
        final data = res.data;
        if (data != null && data.isNotEmpty) {
          _stampBytes = Uint8List.fromList(data);
        }
      }
    } catch (_) {
      _stampBytes = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickAndUploadLogo() async {
    if (_uploadingLogo) return;
    setState(() {
      _uploadingLogo = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      final bytes = f.bytes!;
      await BusinessApiService.uploadLogo(
        businessId: widget.businessId,
        filename: f.name,
        bytes: bytes,
      );
      _logoBytes = Uint8List.fromList(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لوگو با موفقیت ذخیره شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در آپلود لوگو: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingLogo = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadStamp() async {
    if (_uploadingStamp) return;
    setState(() {
      _uploadingStamp = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      final bytes = f.bytes!;
      await BusinessApiService.uploadStamp(
        businessId: widget.businessId,
        filename: f.name,
        bytes: bytes,
      );
      _stampBytes = Uint8List.fromList(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مهر/امضا با موفقیت ذخیره شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در آپلود مهر/امضا: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingStamp = false;
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
              _buildSectionTitle('لوگو و مهر کسب‌وکار', cs),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildLogoCard(cs)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStampCard(cs)),
                ],
              ),

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

  Widget _buildLogoCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.image_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('لوگو', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: _logoBytes != null
                  ? Image.memory(
                      _logoBytes!,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      'لوگویی ثبت نشده است',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                icon: _uploadingLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('انتخاب و آپلود لوگو'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStampCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('مهر / امضای شرکت', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: _stampBytes != null
                  ? Image.memory(
                      _stampBytes!,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      'مهر/امضایی ثبت نشده است',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _uploadingStamp ? null : _pickAndUploadStamp,
                icon: _uploadingStamp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('انتخاب و آپلود مهر / امضا'),
              ),
            ),
          ],
        ),
      ),
    );
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
      initialValue: _businessType,
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
      initialValue: _businessField,
      decoration: InputDecoration(labelText: t.businessField),
      items: BusinessField.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _businessField = val),
      validator: (val) => val == null ? t.businessField : null,
    );
  }
}


