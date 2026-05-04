import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// ویجت نوار جستجوی تنظیمات
class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final String? initialQuery;
  /// حاشهٔ عمودی کمتر برای نمای پهن (دسکتاپ)
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

    return Container(
      margin: EdgeInsets.only(bottom: widget.dense ? 10 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
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
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchSettingsPlaceholder,
                prefixIcon: Icon(
                  Icons.search,
                  color: colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
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
                  color: hasText ? colorScheme.onSurfaceVariant : Colors.transparent,
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

