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


  List<SettingsItem> _getFilteredItems() {
    if (widget.showSearchResults && widget.searchQuery != null) {
      final query = widget.searchQuery!.toLowerCase();
      return widget.category.items.where((item) {
        return item.id.toLowerCase().contains(query) ||
            item.title.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query);
      }).toList();
    }
    return widget.category.items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final filteredItems = _getFilteredItems();

    // اگر جستجو فعال است و آیتمی در این دسته پیدا نشد، نمایش نده
    if (widget.showSearchResults &&
        widget.searchQuery != null &&
        widget.searchQuery!.isNotEmpty &&
        filteredItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          // Header دسته
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpansion,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.category.color.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    // آیکون دسته
                    Icon(
                      widget.category.icon,
                      color: widget.category.color,
                      size: 20,
                    ),
                    const SizedBox(width: 12),

                    // عنوان و توضیحات
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.getCategoryTitle(t, widget.category.title),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // آیکون expand/collapse
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

          // محتوای دسته (آیتم‌ها)
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: ClipRect(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: filteredItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            AppLocalizations.of(context).noSettingsInCategory,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: filteredItems.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SettingsCard(
                              item: item,
                              isHighlighted: widget.showSearchResults &&
                                  widget.searchQuery != null &&
                                  widget.searchQuery!.isNotEmpty,
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

