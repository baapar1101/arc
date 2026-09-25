import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/crm/crm_web_chat_widget_form_dialog.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

/// تنظیمات CRM سطح کسب‌وکار (مثلاً ارسال فایل در چت وب و ویجت‌های چت).
class BusinessCrmSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final ApiClient apiClient;

  const BusinessCrmSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<BusinessCrmSettingsPage> createState() => _BusinessCrmSettingsPageState();
}

class _BusinessCrmSettingsPageState extends State<BusinessCrmSettingsPage> {
  late final CrmChatService _svc;
  late final CrmService _crm;
  bool _loading = true;
  bool _allowFiles = false;
  bool _allowVoice = false;
  bool _saving = false;
  List<dynamic> _widgets = [];

  final TextEditingController _leadSlaCtrl = TextEditingController();
  final TextEditingController _staleDealCtrl = TextEditingController();
  bool _autoAssignEnabled = false;
  bool _followUpNotifyEnabled = false;
  final Set<int> _autoAssignUserIds = {};
  List<Map<String, dynamic>> _businessUsers = [];
  bool _savingAutomation = false;

  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> _wonReasons = [];
  List<Map<String, dynamic>> _lostReasons = [];

  @override
  void initState() {
    super.initState();
    _svc = CrmChatService(apiClient: widget.apiClient);
    _crm = CrmService(apiClient: widget.apiClient);
    _load();
  }

  @override
  void dispose() {
    _leadSlaCtrl.dispose();
    _staleDealCtrl.dispose();
    super.dispose();
  }

  static String _embedSnippet(AppLocalizations t, String apiBase, String publicKey) {
    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    return t.crmWebChatEmbedSnippet(base, publicKey);
  }

  static bool _visitorFileAllowedInWidgetSettings(Map<String, dynamic> w) {
    final s = w['settings'];
    if (s is! Map) return true;
    return s['allow_visitor_file_upload'] != false;
  }

  static bool _visitorVoiceAllowedInWidgetSettings(Map<String, dynamic> w) {
    final s = w['settings'];
    if (s is! Map) return true;
    return s['allow_visitor_voice'] != false;
  }

  Map<String, dynamic> _mergeWidgetSettings(Map<String, dynamic> w, bool allowVisitorFile, bool allowVisitorVoice) {
    final prev = w['settings'];
    final m = <String, dynamic>{};
    if (prev is Map) {
      for (final e in prev.entries) {
        m[e.key.toString()] = e.value;
      }
    }
    if (allowVisitorFile) {
      m.remove('allow_visitor_file_upload');
    } else {
      m['allow_visitor_file_upload'] = false;
    }
    if (allowVisitorVoice) {
      m.remove('allow_visitor_voice');
    } else {
      m['allow_visitor_voice'] = false;
    }
    return m;
  }

  Future<void> _copyText(String text, String successMsg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) SnackBarHelper.show(context, message: successMsg);
  }

  Future<void> _persistCrmFlags({
    required bool files,
    required bool voice,
  }) async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.updateCrmSettings(
        businessId: widget.businessId,
        allowWebChatFileUpload: files,
        allowWebChatVoice: voice,
      );
      if (!mounted) return;
      setState(() {
        _allowFiles = files;
        _allowVoice = voice;
        _saving = false;
      });
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SnackBarHelper.show(
          context,
          message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
    }
  }

  Future<void> _load() async {
    if (!widget.authStore.canReadSection('crm')) return;
    setState(() => _loading = true);
    try {
      final d = await _svc.getCrmSettings(businessId: widget.businessId);
      List<dynamic> w = [];
      if (widget.authStore.canViewCrmWebChat()) {
        w = await _svc.listWidgets(businessId: widget.businessId);
      }
      if (!mounted) return;
      setState(() {
        _allowFiles = d['allow_web_chat_file_upload'] == true;
        _allowVoice = d['allow_web_chat_voice'] == true;
        _widgets = w;
        _loading = false;
      });
      await _loadAutomation();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  Future<void> _setAllowFiles(bool v) async => _persistCrmFlags(files: v, voice: _allowVoice);

  Future<void> _setAllowVoice(bool v) async => _persistCrmFlags(files: _allowFiles, voice: v);

  Future<void> _loadAutomation() async {
    try {
      final results = await Future.wait([
        _crm.getAutomationSettings(businessId: widget.businessId),
        _crm.listTags(businessId: widget.businessId),
        _crm.listCloseReasons(businessId: widget.businessId, reasonType: 'won'),
        _crm.listCloseReasons(businessId: widget.businessId, reasonType: 'lost'),
      ]);
      List<Map<String, dynamic>> users = [];
      try {
        final res = await BusinessUserService(widget.apiClient).getBusinessUsers(widget.businessId);
        users = res.users.map((u) => <String, dynamic>{'id': u.userId, 'name': u.userName}).toList();
      } catch (_) {}
      if (!mounted) return;
      final s = results[0] as Map<String, dynamic>;
      setState(() {
        _leadSlaCtrl.text = (s['lead_sla_hours'] as num?)?.toInt().toString() ?? '';
        _staleDealCtrl.text = (s['stale_deal_days'] as num?)?.toInt().toString() ?? '';
        _autoAssignEnabled = s['auto_assign_enabled'] == true;
        _followUpNotifyEnabled = s['follow_up_notify_enabled'] == true;
        _autoAssignUserIds
          ..clear()
          ..addAll(((s['auto_assign_user_ids'] as List?) ?? []).map((e) => (e as num).toInt()));
        _businessUsers = users;
        _tags = (results[1] as List).cast<Map<String, dynamic>>();
        _wonReasons = (results[2] as List).cast<Map<String, dynamic>>();
        _lostReasons = (results[3] as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  Future<void> _saveAutomation() async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    setState(() => _savingAutomation = true);
    try {
      await _crm.updateAutomationSettings(
        businessId: widget.businessId,
        leadSlaHours: int.tryParse(_leadSlaCtrl.text.trim()),
        autoAssignEnabled: _autoAssignEnabled,
        autoAssignUserIds: _autoAssignUserIds.toList(),
        followUpNotifyEnabled: _followUpNotifyEnabled,
        staleDealDays: int.tryParse(_staleDealCtrl.text.trim()),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'تنظیمات اتوماسیون ذخیره شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _savingAutomation = false);
    }
  }

  Future<void> _addTagDialog() async {
    final nameCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('برچسب جدید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام *', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'رنگ (مثلاً #4CAF50)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('افزودن')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final color = colorCtrl.text.trim();
    nameCtrl.dispose();
    colorCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      await _crm.createTag(businessId: widget.businessId, name: name, color: color.isEmpty ? null : color);
      final tags = await _crm.listTags(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _tags = tags);
      SnackBarHelper.show(context, message: 'برچسب اضافه شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _deleteTag(int id) async {
    try {
      await _crm.deleteTag(businessId: widget.businessId, tagId: id);
      if (!mounted) return;
      setState(() => _tags = _tags.where((t) => (t['id'] as num?)?.toInt() != id).toList());
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _addCloseReasonDialog(String reasonType) async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reasonType == 'won' ? 'دلیل برد جدید' : 'دلیل باخت جدید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'کد * (لاتین)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام *', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('افزودن')),
        ],
      ),
    );
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (ok != true || code.isEmpty || name.isEmpty) return;
    try {
      await _crm.createCloseReason(businessId: widget.businessId, reasonType: reasonType, code: code, name: name);
      final reasons = await _crm.listCloseReasons(businessId: widget.businessId, reasonType: reasonType);
      if (!mounted) return;
      setState(() {
        if (reasonType == 'won') {
          _wonReasons = reasons;
        } else {
          _lostReasons = reasons;
        }
      });
      SnackBarHelper.show(context, message: 'دلیل اضافه شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _deleteCloseReason(String reasonType, int id) async {
    try {
      await _crm.deleteCloseReason(businessId: widget.businessId, reasonId: id);
      if (!mounted) return;
      setState(() {
        if (reasonType == 'won') {
          _wonReasons = _wonReasons.where((r) => (r['id'] as num?)?.toInt() != id).toList();
        } else {
          _lostReasons = _lostReasons.where((r) => (r['id'] as num?)?.toInt() != id).toList();
        }
      });
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _createWidgetDialog() async {
    if (!widget.authStore.canManageCrmWebChatWidgets()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
      return;
    }
    final nameCtrl = TextEditingController();
    final originsCtrl = TextEditingController();
    final res = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CrmWebChatWidgetFormDialog(
        isEdit: false,
        nameController: nameCtrl,
        originsController: originsCtrl,
        initialAllowVisitorFile: true,
        initialAllowVisitorVoice: true,
        initialIsActive: true,
        businessFileUploadEnabled: _allowFiles,
        businessVoiceUploadEnabled: _allowVoice,
      ),
    );
    try {
      if (res == null || res['save'] != true || !mounted) return;
      final allowFile = res['allow_visitor_file'] == true;
      final allowVs = res['allow_visitor_voice'] == true;

      Map<String, dynamic>? merged;
      if (_allowFiles || _allowVoice) {
        merged = {};
        if (_allowFiles && !allowFile) {
          merged['allow_visitor_file_upload'] = false;
        }
        if (_allowVoice && !allowVs) {
          merged['allow_visitor_voice'] = false;
        }
        if (merged.isEmpty) {
          merged = null;
        }
      }

      final raw = originsCtrl.text.trim();
      List<String>? origins;
      if (raw.isNotEmpty) {
        origins = raw.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }

      final t0 = AppLocalizations.of(context);
      await _svc.createWidget(
        businessId: widget.businessId,
        name: nameCtrl.text.trim().isEmpty ? t0.crmWebChatDefaultWidgetName : nameCtrl.text.trim(),
        allowedOrigins: origins,
        settings: merged,
      );
      await _load();
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatWidgetCreated);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    } finally {
      nameCtrl.dispose();
      originsCtrl.dispose();
    }
  }

  Future<void> _editWidgetDialog(Map<String, dynamic> w) async {
    if (!widget.authStore.canManageCrmWebChatWidgets()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
      return;
    }
    final id = (w['id'] as num).toInt();
    final nameCtrl = TextEditingController(text: w['name']?.toString() ?? '');
    final originsCtrl = TextEditingController(
      text: (w['allowed_origins'] is List) ? (w['allowed_origins'] as List).map((e) => e.toString()).join('، ') : '',
    );
    final res = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CrmWebChatWidgetFormDialog(
        isEdit: true,
        nameController: nameCtrl,
        originsController: originsCtrl,
        initialAllowVisitorFile: _visitorFileAllowedInWidgetSettings(w),
        initialAllowVisitorVoice: _visitorVoiceAllowedInWidgetSettings(w),
        initialIsActive: w['is_active'] == true,
        businessFileUploadEnabled: _allowFiles,
        businessVoiceUploadEnabled: _allowVoice,
      ),
    );
    try {
      if (res == null || res['save'] != true || !mounted) return;
      final allowFile = res['allow_visitor_file'] == true;
      final allowVs = res['allow_visitor_voice'] == true;
      final isActive = res['is_active'] == true;
      final raw = originsCtrl.text.trim();
      List<String>? origins;
      if (raw.isNotEmpty) {
        origins = raw.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else {
        origins = const <String>[];
      }
      await _svc.updateWidget(
        businessId: widget.businessId,
        widgetId: id,
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        allowedOrigins: origins,
        settings: (!_allowFiles && !_allowVoice)
            ? null
            : _mergeWidgetSettings(w, allowFile, allowVs),
        isActive: isActive,
      );
      await _load();
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatWidgetUpdated);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    } finally {
      nameCtrl.dispose();
      originsCtrl.dispose();
    }
  }

  Widget _buildReasonList(String reasonType, List<Map<String, dynamic>> reasons, bool canWrite) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reasons.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('دلیلی تعریف نشده است.'))
        else
          ...reasons.map((r) {
            final id = (r['id'] as num?)?.toInt();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(r['name']?.toString() ?? ''),
              subtitle: Text(r['code']?.toString() ?? ''),
              trailing: (canWrite && id != null)
                  ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteCloseReason(reasonType, id))
                  : null,
            );
          }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: canWrite ? () => _addCloseReasonDialog(reasonType) : null,
            icon: const Icon(Icons.add),
            label: const Text('افزودن دلیل'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return const AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    final canWrite = widget.authStore.canWriteSection('crm');
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final apiBase = AppConfig.apiBaseUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات CRM'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          title: const Text('ارسال فایل در چت وب'),
                          subtitle: const Text(
                            'اگر فعال باشد، بازدیدکنندگان ویجت چت می‌توانند تصویر و فایل بفرستند. '
                            'نیاز به پلن فضای ذخیره‌سازی فعال و ظرفیت کافی دارد.',
                          ),
                          value: _allowFiles,
                          onChanged: (!canWrite || _saving) ? null : (v) => unawaited(_setAllowFiles(v)),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(t.crmSettingsWebChatVoiceTitle),
                          subtitle: Text(t.crmSettingsWebChatVoiceSubtitle),
                          value: _allowVoice,
                          onChanged: (!canWrite || _saving) ? null : (v) => unawaited(_setAllowVoice(v)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CrmSectionCard(
                  title: 'اتوماسیون فروش',
                  subtitle: 'قوانین SLA، تخصیص خودکار و پیگیری‌ها.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _leadSlaCtrl,
                              enabled: canWrite,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'مهلت SLA سرنخ (ساعت)', isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _staleDealCtrl,
                              enabled: canWrite,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'روزهای رکود معامله', isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('تخصیص خودکار سرنخ‌ها'),
                        value: _autoAssignEnabled,
                        onChanged: canWrite ? (v) => setState(() => _autoAssignEnabled = v) : null,
                      ),
                      if (_autoAssignEnabled && _businessUsers.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 8),
                          child: Align(alignment: Alignment.centerRight, child: Text('کاربران مجاز برای تخصیص:')),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _businessUsers.map((u) {
                            final id = (u['id'] as num?)?.toInt();
                            if (id == null) return const SizedBox.shrink();
                            final selected = _autoAssignUserIds.contains(id);
                            return FilterChip(
                              label: Text(u['name']?.toString() ?? '#$id'),
                              selected: selected,
                              onSelected: canWrite
                                  ? (v) => setState(() {
                                        if (v) {
                                          _autoAssignUserIds.add(id);
                                        } else {
                                          _autoAssignUserIds.remove(id);
                                        }
                                      })
                                  : null,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('اعلان پیگیری‌ها'),
                        value: _followUpNotifyEnabled,
                        onChanged: canWrite ? (v) => setState(() => _followUpNotifyEnabled = v) : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: (!canWrite || _savingAutomation) ? null : _saveAutomation,
                          icon: _savingAutomation
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: const Text('ذخیره تنظیمات اتوماسیون'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CrmSectionCard(
                  title: 'برچسب‌ها',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_tags.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('برچسبی تعریف نشده است.'))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tags.map((t) {
                            final id = (t['id'] as num?)?.toInt();
                            return Chip(
                              label: Text(t['name']?.toString() ?? ''),
                              onDeleted: (canWrite && id != null) ? () => _deleteTag(id) : null,
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: canWrite ? _addTagDialog : null,
                          icon: const Icon(Icons.add),
                          label: const Text('افزودن برچسب'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CrmSectionCard(
                  title: 'دلایل برد',
                  child: _buildReasonList('won', _wonReasons, canWrite),
                ),
                const SizedBox(height: 16),
                CrmSectionCard(
                  title: 'دلایل باخت',
                  child: _buildReasonList('lost', _lostReasons, canWrite),
                ),
                if (widget.authStore.canViewCrmWebChat()) ...[
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.widgets_outlined, color: cs.primary, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.crmWebChatWidgetsSectionTitle,
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      t.crmWebChatCrmSettingsWidgetsIntro,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (widget.authStore.canManageCrmWebChatWidgets()) ...[
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: _createWidgetDialog,
                              icon: const Icon(Icons.add),
                              label: Text(t.crmWebChatAddWidgetButton),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_widgets.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                t.crmWebChatCrmSettingsNoWidgets,
                                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            )
                          else
                            ..._widgets.map((raw) {
                              final w = raw as Map<String, dynamic>;
                              final pk = w['public_key']?.toString() ?? '';
                              final name = w['name']?.toString() ?? t.crmWebChatDefaultWidgetName;
                              final active = w['is_active'] == true;
                              final guestFile = _visitorFileAllowedInWidgetSettings(w);
                              final guestVoice = _visitorVoiceAllowedInWidgetSettings(w);
                              final fileHint = !_allowFiles
                                  ? t.crmWebChatVisitorAttachmentCrmOff
                                  : (guestFile
                                      ? t.crmWebChatVisitorAttachmentAllowed
                                      : t.crmWebChatVisitorAttachmentWidgetOff);
                              final voiceHint = !_allowVoice
                                  ? t.crmWebChatVisitorVoiceSwitchOff
                                  : (guestVoice
                                      ? t.crmWebChatVisitorVoiceSwitchOn
                                      : t.crmWebChatVisitorVoiceOffWidget);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                child: ListTile(
                                  dense: true,
                                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  isThreeLine: true,
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        active ? t.crmWebChatWidgetStateActive : t.crmWebChatWidgetStateInactive,
                                        style: TextStyle(
                                          color: active ? cs.primary : cs.error,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fileHint,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        voiceHint,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (k) {
                                      if (k == 'copy_pk') {
                                        unawaited(_copyText(pk, t.crmWebChatPublicKeyCopied));
                                      } else if (k == 'copy_embed') {
                                        unawaited(
                                          _copyText(
                                            _embedSnippet(t, apiBase, pk),
                                            t.crmWebChatEmbedGuideCopied,
                                          ),
                                        );
                                      } else if (k == 'edit' && widget.authStore.canManageCrmWebChatWidgets()) {
                                        _editWidgetDialog(w);
                                      }
                                    },
                                    itemBuilder: (c) => [
                                      PopupMenuItem(value: 'copy_pk', child: Text(t.crmWebChatMenuCopyPublicKey)),
                                      PopupMenuItem(value: 'copy_embed', child: Text(t.crmWebChatMenuCopyApiGuide)),
                                      if (widget.authStore.canManageCrmWebChatWidgets())
                                        PopupMenuItem(value: 'edit', child: Text(t.crmWebChatMenuEdit)),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
