import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../utils/responsive_helper.dart';

/// شِل رسپانسیو برای دیالوگ‌های ایمپورت اکسل — موبایل تمام‌صفحه با اسکرول، دسکتاپ با عرض محدود.
class ExcelImportDialogShell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final VoidCallback? onClose;

  const ExcelImportDialogShell({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.maxWidth = 560,
    this.onClose,
  });

  void _handleClose(BuildContext context) {
    if (onClose == null) return;
    onClose!();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final insets = media.viewInsets;

    final scrollContent = SingleChildScrollView(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        top: isMobile ? 4 : 8,
        bottom: padding.bottom + insets.bottom + 8,
      ),
      child: child,
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Container(
          width: media.size.width,
          height: media.size.height,
          margin: EdgeInsets.only(
            top: padding.top + 8,
            bottom: padding.bottom + 8,
            left: 10,
            right: 10,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _MobileTitleBar(title: title, onClose: () => _handleClose(context)),
              Expanded(child: scrollContent),
              if (actions.isNotEmpty) _MobileActions(actions: actions),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: onClose == null ? null : () => _handleClose(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(child: scrollContent),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileTitleBar extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;

  const _MobileTitleBar({required this.title, this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
            tooltip: t.dialogClose,
          ),
        ],
      ),
    );
  }
}

class _MobileActions extends StatelessWidget {
  final List<Widget> actions;

  const _MobileActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    final stackVertically = actions.length >= 3;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: stackVertically
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i < actions.length - 1 ? 8 : 0),
                      child: _stretchAction(actions[i]),
                    ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
      ),
    );
  }

  Widget _stretchAction(Widget action) {
    return SizedBox(width: double.infinity, child: action);
  }
}

/// انتخاب فایل اکسل — کارت فایل + دکمه انتخاب؛ بدون ردیف فشرده در موبایل.
class ExcelImportFilePicker extends StatelessWidget {
  final String? fileName;
  final String emptyHint;
  final String chooseLabel;
  final VoidCallback? onPick;
  final bool enabled;

  const ExcelImportFilePicker({
    super.key,
    required this.fileName,
    required this.emptyHint,
    required this.chooseLabel,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFile = fileName != null && fileName!.isNotEmpty;
    final displayName = hasFile ? fileName! : emptyHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hasFile
                ? cs.primaryContainer.withValues(alpha: 0.25)
                : cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile
                  ? cs.primary.withValues(alpha: 0.45)
                  : cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasFile ? Icons.insert_drive_file_outlined : Icons.upload_file_outlined,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!hasFile)
                      Text(
                        emptyHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.attach_file),
          label: Text(chooseLabel),
        ),
      ],
    );
  }
}

/// فیلد انتخاب با برچسب جدا — متن آیتم‌ها کوتاه و بدون overflow.
class ExcelImportDropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;

  const ExcelImportDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: _fieldDecoration(context, label),
      items: items,
      onChanged: onChanged,
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String label) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

/// چیدمان عمودی در موبایل و دو ستونه در دسکتاپ.
class ExcelImportResponsiveGroup extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const ExcelImportResponsiveGroup({
    super.key,
    required this.children,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) SizedBox(height: spacing),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}

/// بنر اطلاعاتی با متن چندخطی.
class ExcelImportInfoBanner extends StatelessWidget {
  final String message;

  const ExcelImportInfoBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
