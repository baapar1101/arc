import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/warranty_service.dart';
import '../../models/warranty_models.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';

class WarrantySettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const WarrantySettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<WarrantySettingsPage> createState() => _WarrantySettingsPageState();
}

class _WarrantySettingsPageState extends State<WarrantySettingsPage> {
  final WarrantyService _warrantyService = WarrantyService();
  bool _loading = false;
  bool _saving = false;
  WarrantySetting? _settings;

  final _formKey = GlobalKey<FormState>();
  String _codeFormat = 'random';
  String? _codePrefix;
  String _serialFormat = 'random';
  int? _serialLength;
  bool _requireSerialVerification = false;
  bool _requireProductInstanceMatch = false;
  int? _maxActivationAttempts;
  int? _activationLockoutDurationMinutes;
  bool _requireCustomerRegistration = false;
  bool _autoLinkToPerson = true;
  bool _enableTrackingLink = true;
  int? _trackingLinkExpiresDays;
  bool _enableSmsNotification = false;
  bool _enableEmailNotification = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final settings = await _warrantyService.getSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _settings = settings;
          _codeFormat = settings.codeFormat;
          _codePrefix = settings.codePrefix;
          _serialFormat = settings.serialFormat;
          _serialLength = settings.serialLength;
          _requireSerialVerification = settings.requireSerialVerification;
          _requireProductInstanceMatch = settings.requireProductInstanceMatch;
          _maxActivationAttempts = settings.maxActivationAttempts;
          _activationLockoutDurationMinutes = settings.activationLockoutDurationMinutes;
          _requireCustomerRegistration = settings.requireCustomerRegistration;
          _autoLinkToPerson = settings.autoLinkToPerson;
          _enableTrackingLink = settings.enableTrackingLink;
          _trackingLinkExpiresDays = settings.trackingLinkExpiresDays;
          _enableSmsNotification = settings.enableSmsNotification;
          _enableEmailNotification = settings.enableEmailNotification;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری تنظیمات: $e');
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final payload = {
        'code_format': _codeFormat,
        'code_prefix': _codePrefix,
        'serial_format': _serialFormat,
        'serial_length': _serialLength,
        'require_serial_verification': _requireSerialVerification,
        'require_product_instance_match': _requireProductInstanceMatch,
        'max_activation_attempts': _maxActivationAttempts,
        'activation_lockout_duration_minutes': _activationLockoutDurationMinutes,
        'require_customer_registration': _requireCustomerRegistration,
        'auto_link_to_person': _autoLinkToPerson,
        'enable_tracking_link': _enableTrackingLink,
        'tracking_link_expires_days': _trackingLinkExpiresDays,
        'enable_sms_notification': _enableSmsNotification,
        'enable_email_notification': _enableEmailNotification,
      };
      await _warrantyService.updateSettings(widget.businessId, payload);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'تنظیمات با موفقیت ذخیره شد');
        _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در ذخیره تنظیمات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.warrantySettings),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection(
                      context,
                      title: 'فرمت کد و سریال',
                      children: [
                        _buildCodeFormatSection(context, theme),
                        const SizedBox(height: 16),
                        _buildSerialFormatSection(context, theme),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: t.warrantySecuritySettings,
                      children: [
                        SwitchListTile(
                          title: Text(t.warrantyRequireSerialVerification),
                          value: _requireSerialVerification,
                          onChanged: (value) =>
                              setState(() => _requireSerialVerification = value),
                        ),
                        SwitchListTile(
                          title: Text(t.warrantyRequireProductInstanceMatch),
                          value: _requireProductInstanceMatch,
                          onChanged: (value) =>
                              setState(() => _requireProductInstanceMatch = value),
                        ),
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: t.warrantyMaxActivationAttempts,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          initialValue: _maxActivationAttempts?.toString(),
                          onChanged: (value) =>
                              _maxActivationAttempts = int.tryParse(value),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: t.warrantyActivationLockoutDuration,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          initialValue: _activationLockoutDurationMinutes?.toString(),
                          onChanged: (value) =>
                              _activationLockoutDurationMinutes = int.tryParse(value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'تنظیمات مشتری',
                      children: [
                        SwitchListTile(
                          title: const Text('الزام ثبت مشتری در سیستم'),
                          subtitle: const Text('در صورت فعال بودن، مشتری باید در سیستم ثبت شده باشد'),
                          value: _requireCustomerRegistration,
                          onChanged: (value) => setState(() => _requireCustomerRegistration = value),
                        ),
                        SwitchListTile(
                          title: Text(t.warrantyAutoLinkToPerson),
                          value: _autoLinkToPerson,
                          onChanged: (value) => setState(() => _autoLinkToPerson = value),
                        ),
                        SwitchListTile(
                          title: Text(t.warrantyEnableTrackingLink),
                          value: _enableTrackingLink,
                          onChanged: (value) => setState(() => _enableTrackingLink = value),
                        ),
                        if (_enableTrackingLink)
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: t.warrantyTrackingLinkExpiresDays,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            initialValue: _trackingLinkExpiresDays?.toString(),
                            onChanged: (value) =>
                                _trackingLinkExpiresDays = int.tryParse(value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'اعلان‌رسانی',
                      children: [
                        SwitchListTile(
                          title: Text(t.warrantyEnableSmsNotification),
                          value: _enableSmsNotification,
                          onChanged: (value) =>
                              setState(() => _enableSmsNotification = value),
                        ),
                        SwitchListTile(
                          title: Text(t.warrantyEnableEmailNotification),
                          value: _enableEmailNotification,
                          onChanged: (value) =>
                              setState(() => _enableEmailNotification = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _saving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('ذخیره تنظیمات'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<Widget> children}) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildCodeFormatSection(BuildContext context, ThemeData theme) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.warrantyCodeFormat,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'random', label: Text(t.warrantyRandom)),
            ButtonSegment(value: 'sequential', label: Text(t.warrantySequential)),
            ButtonSegment(value: 'custom', label: Text(t.warrantyCustom)),
          ],
          selected: {_codeFormat},
          onSelectionChanged: (Set<String> newSelection) {
            setState(() => _codeFormat = newSelection.first);
          },
        ),
        if (_codeFormat == 'sequential' || _codeFormat == 'random') ...[
          const SizedBox(height: 16),
          TextFormField(
            decoration: InputDecoration(
              labelText: t.warrantyCodePrefix,
              border: const OutlineInputBorder(),
              hintText: 'مثال: WR-',
            ),
            initialValue: _codePrefix,
            onChanged: (value) => _codePrefix = value.isEmpty ? null : value,
          ),
        ],
      ],
    );
  }

  Widget _buildSerialFormatSection(BuildContext context, ThemeData theme) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.warrantySerialFormat,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'random', label: Text(t.warrantyRandom)),
            ButtonSegment(value: 'custom', label: Text(t.warrantyCustom)),
          ],
          selected: {_serialFormat},
          onSelectionChanged: (Set<String> newSelection) {
            setState(() => _serialFormat = newSelection.first);
          },
        ),
        if (_serialFormat == 'random') ...[
          const SizedBox(height: 16),
          TextFormField(
            decoration: InputDecoration(
              labelText: t.warrantySerialLength,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            initialValue: _serialLength?.toString(),
            onChanged: (value) => _serialLength = int.tryParse(value),
          ),
        ],
      ],
    );
  }
}

