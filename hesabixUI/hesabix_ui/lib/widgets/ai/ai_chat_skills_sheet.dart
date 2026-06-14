import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/business_nav.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/ai/ai_skill_publish_dialog.dart';

/// مدیریت مهارت‌های AI نصب‌شده (فعال/غیرفعال، import ZIP).
Future<void> showAIChatSkillsSheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
  void Function(String relativePath)? onOpenPanelPage,
}) async {
  if (businessId == null) {
    SnackBarHelper.show(context, message: 'ابتدا یک کسب‌وکار انتخاب کنید', isError: true);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AIChatSkillsSheet(
      aiService: aiService,
      businessId: businessId,
      onOpenPanelPage: onOpenPanelPage,
    ),
  );
}

class _AIChatSkillsSheet extends StatefulWidget {
  final AIService aiService;
  final int businessId;
  final void Function(String relativePath)? onOpenPanelPage;

  const _AIChatSkillsSheet({
    required this.aiService,
    required this.businessId,
    this.onOpenPanelPage,
  });

  @override
  State<_AIChatSkillsSheet> createState() => _AIChatSkillsSheetState();
}

class _AIChatSkillsSheetState extends State<_AIChatSkillsSheet> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _installs = [];
  List<Map<String, dynamic>> _owned = [];
  List<Map<String, dynamic>> _anthropicCatalog = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final installs = await widget.aiService.listInstalledSkills(businessId: widget.businessId);
      final owned = await widget.aiService.listOwnedSkills(businessId: widget.businessId);
      final catalog = await widget.aiService.listAnthropicSkillCatalog();
      if (!mounted) return;
      setState(() {
        _installs = installs;
        _owned = owned;
        _anthropicCatalog = catalog;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> install, bool enabled) async {
    final id = install['id'];
    if (id == null) return;
    final installId = id is int ? id : int.tryParse(id.toString());
    if (installId == null) return;
    setState(() => _busy = true);
    try {
      await widget.aiService.setSkillsEnabled(
        businessId: widget.businessId,
        enableIds: enabled ? [installId] : null,
        disableIds: enabled ? null : [installId],
      );
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      await widget.aiService.importSkillZip(
        businessId: widget.businessId,
        filename: f.name,
        bytes: bytes,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت وارد شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importGit() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('وارد کردن از گیت‌هاب'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'https://github.com/...',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('وارد کردن')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.aiService.importSkillFromGit(
        businessId: widget.businessId,
        gitUrl: ctrl.text.trim(),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت از گیت‌هاب وارد شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _visibilityLabel(String? v) {
    switch (v) {
      case 'draft':
        return 'پیش‌نویس';
      case 'pending_review':
        return 'در انتظار بررسی';
      case 'published':
        return 'منتشر شده';
      case 'hidden':
        return 'رد شده';
      case 'business_only':
        return 'محلی';
      default:
        return v ?? '';
    }
  }

  bool _canPublish(String? visibility) {
    return visibility == 'draft' || visibility == 'business_only' || visibility == 'hidden';
  }

  Future<void> _publish(Map<String, dynamic> pkg) async {
    final id = pkg['id'];
    final packageId = id is int ? id : int.tryParse('$id');
    if (packageId == null) return;
    final ok = await AISkillPublishDialog.show(
      context,
      businessId: widget.businessId,
      packageId: packageId,
      defaultTitle: pkg['title']?.toString() ?? '',
    );
    if (ok == true) await _load();
  }

  Future<void> _installAnthropic(String skillId) async {
    setState(() => _busy = true);
    try {
      await widget.aiService.installAnthropicSkill(
        businessId: widget.businessId,
        anthropicSkillId: skillId,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت Anthropic نصب شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPanelPage(String relativePath) {
    final onOpenPanelPage = widget.onOpenPanelPage;
    if (onOpenPanelPage != null) {
      Navigator.of(context).pop();
      onOpenPanelPage(relativePath);
      return;
    }
    final path = context.businessPanelUrl(widget.businessId, relativePath);
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('مهارت‌های AI', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _importZip,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('وارد کردن ZIP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importGit,
                    icon: const Icon(Icons.code_rounded, size: 18),
                    label: const Text('گیت‌هاب'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _openPanelPage('ai/skills/marketplace'),
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: const Text('مارکت‌پلیس'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _openPanelPage('ai/skills/publisher'),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('درآمد'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Text('نصب‌شده', style: theme.textTheme.titleSmall),
                      if (_installs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('مهارتی نصب نشده است.'),
                        )
                      else
                        ..._installs.map((inst) {
                          final pkg = Map<String, dynamic>.from(inst['package'] as Map? ?? {});
                          final title = pkg['title']?.toString() ?? pkg['skill_slug']?.toString() ?? '—';
                          final source = pkg['source_type']?.toString() ?? '';
                          final enabled = inst['is_enabled'] == true;
                          return SwitchListTile(
                            title: Text(title),
                            subtitle: Text(source),
                            value: enabled,
                            onChanged: _busy ? null : (v) => _toggle(inst, v),
                          );
                        }),
                      const Divider(height: 24),
                      Text('مهارت‌های من', style: theme.textTheme.titleSmall),
                      if (_owned.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('مهارتی وارد نشده. ZIP یا گیت‌هاب را امتحان کنید.'),
                        )
                      else
                        ..._owned.map((pkg) {
                          final title = pkg['title']?.toString() ?? pkg['skill_slug']?.toString() ?? '—';
                          final vis = pkg['visibility']?.toString();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(title),
                            subtitle: Text(_visibilityLabel(vis)),
                            trailing: _canPublish(vis)
                                ? TextButton(
                                    onPressed: _busy ? null : () => _publish(pkg),
                                    child: const Text('انتشار'),
                                  )
                                : null,
                          );
                        }),
                      const Divider(height: 24),
                      Text('کتابخانه Anthropic', style: theme.textTheme.titleSmall),
                      ..._anthropicCatalog.map((item) {
                        final sid = item['anthropic_skill_id']?.toString() ?? '';
                        return ListTile(
                          title: Text(item['title']?.toString() ?? sid),
                          subtitle: Text(item['description']?.toString() ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _busy || sid.isEmpty ? null : () => _installAnthropic(sid),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
