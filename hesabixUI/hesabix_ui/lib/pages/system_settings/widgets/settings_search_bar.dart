import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../theme/tokens/extensions.dart';

/// ویجت نوار جستجوی تنظیمات
class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final String? initialQuery;
  /// حاشیه و پدینگ فشرده برای نمای هاب
  final bool dense;

  const SettingsSearchBar({
    super.key,
    required this.onSearchChanged,
    this.initialQuery,
    this.dense = false,
  });

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.addListener(() {
      widget.onSearchChanged(_controller.text);
    });
  }

  @override
  void didUpdateWidget(SettingsSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local editing state; only sync when parent clears search externally.
    if (widget.initialQuery != oldWidget.initialQuery &&
        (widget.initialQuery ?? '').isEmpty &&
        _controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _controller.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hub = context.settingsHub;
    final iconBox = hub.searchIconSize + 16;

    return Container(
      margin: hub.searchMarginFor(dense: widget.dense),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(hub.searchRadius),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: widget.dense ? hub.cardTitleFontSize : 14,
                height: hub.labelHeight,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchSettingsPlaceholder,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: widget.dense ? hub.cardSubtitleFontSize : 13,
                  height: hub.labelHeight,
                ),
                isDense: true,
                prefixIcon: Icon(
                  Icons.search,
                  size: hub.searchIconSize,
                  color: colorScheme.onSurfaceVariant,
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: iconBox,
                  minHeight: iconBox,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: hub.searchContentPaddingFor(dense: widget.dense),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final hasText = _controller.text.isNotEmpty;
              return IconButton(
                icon: Icon(
                  Icons.clear,
                  size: hub.searchIconSize,
                  color: hasText ? colorScheme.onSurfaceVariant : Colors.transparent,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: iconBox,
                  height: iconBox,
                ),
                onPressed: hasText ? _clearSearch : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
