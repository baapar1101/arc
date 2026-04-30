import 'package:flutter/material.dart';

import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// دیالوگ ایجاد / ویرایش ویجت چت وب CRM.
class CrmWebChatWidgetFormDialog extends StatefulWidget {
  const CrmWebChatWidgetFormDialog({
    super.key,
    required this.isEdit,
    required this.nameController,
    required this.originsController,
    required this.initialAllowVisitorFile,
    required this.initialAllowVisitorVoice,
    required this.initialIsActive,
    required this.businessFileUploadEnabled,
    required this.businessVoiceUploadEnabled,
  });

  final bool isEdit;
  final TextEditingController nameController;
  final TextEditingController originsController;
  final bool initialAllowVisitorFile;
  final bool initialAllowVisitorVoice;
  final bool initialIsActive;
  final bool businessFileUploadEnabled;
  final bool businessVoiceUploadEnabled;

  @override
  State<CrmWebChatWidgetFormDialog> createState() => _CrmWebChatWidgetFormDialogState();
}

class _CrmWebChatWidgetFormDialogState extends State<CrmWebChatWidgetFormDialog> {
  late bool _allowVisitorFile;
  late bool _allowVisitorVoice;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _allowVisitorFile = widget.initialAllowVisitorFile;
    _allowVisitorVoice = widget.initialAllowVisitorVoice;
    _isActive = widget.initialIsActive;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.chat_bubble_outline_rounded, color: cs.onPrimaryContainer, size: 26),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isEdit ? t.crmWebChatWidgetDialogTitleEdit : t.crmWebChatWidgetDialogTitleNew,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.crmWebChatWidgetDialogIntro,
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
                const SizedBox(height: 20),
                TextField(
                  controller: widget.nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: t.crmWebChatWidgetNameLabel,
                    hintText: t.crmWebChatWidgetNameHint,
                    helperText: t.crmWebChatWidgetNameHelper,
                    helperMaxLines: 2,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: widget.originsController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t.crmWebChatWidgetOriginsLabel,
                    hintText: t.crmWebChatWidgetOriginsHint,
                    helperText: t.crmWebChatWidgetOriginsHelper,
                    helperMaxLines: 4,
                    filled: true,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.crmWebChatVisitorFileSwitchTitle),
                      subtitle: Text(
                        widget.businessFileUploadEnabled
                            ? t.crmWebChatVisitorFileSwitchOn
                            : t.crmWebChatVisitorFileSwitchOff,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      value: _allowVisitorFile && widget.businessFileUploadEnabled,
                      onChanged: widget.businessFileUploadEnabled
                          ? (v) => setState(() {
                                _allowVisitorFile = v;
                              })
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.crmWebChatVisitorVoiceSwitchTitle),
                      subtitle: Text(
                        widget.businessVoiceUploadEnabled
                            ? t.crmWebChatVisitorVoiceSwitchOn
                            : t.crmWebChatVisitorVoiceSwitchOff,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      value: _allowVisitorVoice && widget.businessVoiceUploadEnabled,
                      onChanged: widget.businessVoiceUploadEnabled
                          ? (v) => setState(() {
                                _allowVisitorVoice = v;
                              })
                          : null,
                    ),
                  ),
                ),
                if (widget.isEdit) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.crmWebChatWidgetActiveTitle),
                    subtitle: Text(
                      t.crmWebChatWidgetActiveSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (widget.nameController.text.trim().isEmpty) {
                          SnackBarHelper.show(
                            context,
                            message: t.crmWebChatNameRequired,
                            isError: true,
                          );
                          return;
                        }
                        Navigator.pop(context, <String, dynamic>{
                          'save': true,
                          'allow_visitor_file': _allowVisitorFile,
                          'allow_visitor_voice': _allowVisitorVoice,
                          'is_active': _isActive,
                        });
                      },
                      child: Text(widget.isEdit ? t.save : t.crmWebChatCreate),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
