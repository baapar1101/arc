import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/workflow_marketplace_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

/// دیالوگ انتشار ورک‌فلو در مخزن
class WorkflowPublishToMarketplaceDialog extends StatefulWidget {
  final int businessId;
  final int workflowId;
  final String defaultTitle;

  const WorkflowPublishToMarketplaceDialog({
    super.key,
    required this.businessId,
    required this.workflowId,
    required this.defaultTitle,
  });

  @override
  State<WorkflowPublishToMarketplaceDialog> createState() => _WorkflowPublishToMarketplaceDialogState();
}

class _WorkflowPublishToMarketplaceDialogState extends State<WorkflowPublishToMarketplaceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _shortCtrl = TextEditingController();
  final _longCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _versionCtrl = TextEditingController(text: '1.0.0');
  final _changelogCtrl = TextEditingController();
  final WorkflowMarketplaceService _service = WorkflowMarketplaceService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.defaultTitle;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _tagsCtrl.dispose();
    _versionCtrl.dispose();
    _changelogCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations t) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final tagsRaw = _tagsCtrl.text.trim();
      final tags = tagsRaw.isEmpty
          ? <String>[]
          : tagsRaw.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await _service.publish(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        title: _titleCtrl.text.trim(),
        shortDescription: _shortCtrl.text.trim().isEmpty ? null : _shortCtrl.text.trim(),
        longDescription: _longCtrl.text.trim().isEmpty ? null : _longCtrl.text.trim(),
        tags: tags,
        versionLabel: _versionCtrl.text.trim().isEmpty ? '1.0.0' : _versionCtrl.text.trim(),
        changelog: _changelogCtrl.text.trim().isEmpty ? null : _changelogCtrl.text.trim(),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.workflowMarketplacePublishSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.workflowMarketplacePublish),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplacePublishTitleLabel),
                validator: (v) => (v == null || v.trim().isEmpty) ? t.workflowNodeFieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplaceShortDescriptionLabel),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _longCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplaceLongDescriptionLabel),
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplaceTagsLabel),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _versionCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplaceVersionLabel),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _changelogCtrl,
                decoration: InputDecoration(labelText: t.workflowMarketplaceChangelog),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(t.workflowCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _submit(t),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.workflowMarketplacePublishSubmit),
        ),
      ],
    );
  }
}
