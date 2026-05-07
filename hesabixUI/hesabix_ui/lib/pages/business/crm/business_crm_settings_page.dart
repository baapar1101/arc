import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_web_chat_widget_form_dialog.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

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
  bool _loading = true;
  bool _allowFiles = false;
  bool _allowVoice = false;
  bool _saving = false;
  List<dynamic> _widgets = [];

  @override
  void initState() {
    super.initState();
    _svc = CrmChatService(apiClient: widget.apiClient);
    _load();
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

  Future<void> _createWidgetDialog() async {
    if (!widget.authStore.canManageCrmWebChatWidgets()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
      return;
    }
    final nameCtrl = TextEditingController();
    final originsCtrl = TextEditingController();
    final res = await showDialog<Map<String, dynamic>>(
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
    final res = await showDialog<Map<String, dynamic>>(
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/settings'),
        ),
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
