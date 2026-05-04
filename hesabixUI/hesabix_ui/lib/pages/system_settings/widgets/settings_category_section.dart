import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../models/settings_category.dart';
import '../models/settings_item.dart';
import '../utils/localization_helper.dart';
import 'settings_card.dart';

/// ویجت بخش دسته‌بندی تنظیمات
class SettingsCategorySection extends StatefulWidget {
  final SettingsCategory category;
  final bool isExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String? searchQuery;
  final bool showSearchResults;

  const SettingsCategorySection({
    super.key,
    required this.category,
    this.isExpanded = true,
    this.onExpansionChanged,
    this.searchQuery,
    this.showSearchResults = false,
  });

  @override
  State<SettingsCategorySection> createState() =>
      _SettingsCategorySectionState();
}

class _SettingsCategorySectionState extends State<SettingsCategorySection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SettingsCategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      _isExpanded = widget.isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
      widget.onExpansionChanged?.call(_isExpanded);
    });
  }

  static const double _kTwoColumnMinWidth = 720;

  Widget _buildItemsGrid(
    BuildContext context,
    List<SettingsItem> items,
    double maxWidth,
  ) {
    final bool twoColumns = maxWidth >= _kTwoColumnMinWidth;

    Widget cardWrap(SettingsItem item) {
      return SettingsCard(
        item: item,
        isHighlighted: widget.showSearchResults &&
            widget.searchQuery != null &&
            widget.searchQuery!.isNotEmpty,
      );
    }

    if (!twoColumns) {
      return Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: cardWrap(item),
            ),
        ],
      );
    }

    const double gap = 8;
    final double halfWidth = (maxWidth - gap) / 2;
    return Wrap(
      spacing: gap,
      runSpacing: 6,
      children: items
          .map(
            (item) => SizedBox(
              width: halfWidth,
              child: cardWrap(item),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final items = widget.category.items;

    final bool screenWideDesktop = MediaQuery.sizeOf(context).width >= 900;
    final hzHeader = screenWideDesktop ? 10.0 : 16.0;
    final vtHeader = screenWideDesktop ? 10.0 : 12.0;
    final hzBody = screenWideDesktop ? 10.0 : 16.0;
    final vtBody = screenWideDesktop ? 6.0 : 8.0;
    final sectionBottom = screenWideDesktop ? 8.0 : 12.0;

    if (widget.showSearchResults &&
        widget.searchQuery != null &&
        widget.searchQuery!.isNotEmpty &&
        items.isEmpty) {
      return const SizedBox.shrink();
    }

    final categorySubtitle = LocalizationHelper.getCategoryDescription(
      t,
      widget.category.description,
    );

    return Container(
      margin: EdgeInsets.only(bottom: sectionBottom),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpansion,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: hzHeader,
                  vertical: vtHeader,
                ),
                decoration: BoxDecoration(
                  color: widget.category.color.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.category.icon,
                      color: widget.category.color,
                      size: 20,
                    ),
                    SizedBox(width: screenWideDesktop ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.getCategoryTitle(
                              t,
                              widget.category.title,
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              fontSize: 15,
                            ),
                          ),
                          if (categorySubtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              categorySubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.expand_more,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hzBody,
                      vertical: vtBody,
                    ),
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                AppLocalizations.of(context).noSettingsInCategory,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color:
                                      colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          )
                        : _buildItemsGrid(
                            context,
                            items,
                            constraints.maxWidth,
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
