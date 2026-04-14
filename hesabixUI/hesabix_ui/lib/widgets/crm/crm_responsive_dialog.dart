import 'package:flutter/material.dart';

/// دیالوگ رسپانسیو برای فرم‌های CRM؛ در موبایل تمام‌صفحه یا نزدیک به آن، در دسکتاپ با حداکثر عرض محدود.
class CrmResponsiveDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool scrollable;
  final double? maxWidth;

  const CrmResponsiveDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.scrollable = true,
    this.maxWidth,
  });

  static const double _mobileBreakpoint = 600;
  static const double _defaultMaxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isNarrow = media.size.width < _mobileBreakpoint;
    final maxW = maxWidth ?? _defaultMaxWidth;
    final padding = media.padding;
    final insets = media.viewInsets;

    final content = scrollable
        ? SingleChildScrollView(
            child: child,
            padding: EdgeInsets.only(
              bottom: padding.bottom + insets.bottom + 24,
              left: padding.left + 20,
              right: padding.right + 20,
            ),
          )
        : Padding(
            padding: EdgeInsets.only(
              left: padding.left + 20,
              right: padding.right + 20,
              bottom: padding.bottom + insets.bottom,
            ),
            child: child,
          );

    if (isNarrow) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Container(
          width: media.size.width,
          height: media.size.height,
          margin: EdgeInsets.only(
            top: padding.top + 8,
            bottom: padding.bottom + 8,
            left: 12,
            right: 12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildTitleBar(context, isNarrow),
              Flexible(
                child: content,
              ),
              if (actions != null && actions!.isNotEmpty) _buildActions(context),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(title),
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: media.size.height * 0.75,
        ),
        child: content,
      ),
      actions: actions,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsOverflowButtonSpacing: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context, bool isNarrow) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isNarrow)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'بستن',
            ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: actions!
              .map((a) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: a,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
