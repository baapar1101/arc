import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../system_settings/models/settings_category.dart';
import '../../../system_settings/models/settings_item.dart';
import '../business_settings_layout.dart';
import '../business_settings_localization_helper.dart';
import 'business_settings_card.dart';

typedef BusinessSettingsItemTap = void Function(SettingsItem item);

/// Collapsible category section for the business settings hub.
class BusinessSettingsCategorySection extends StatefulWidget {
  final SettingsCategory category;
  final bool isExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String? searchQuery;
  final bool showSearchResults;
  final BusinessSettingsItemTap? onItemTap;
  final String? loadingItemId;
  final bool pluginsLoading;

  const BusinessSettingsCategorySection({
    super.key,
    required this.category,
    this.isExpanded = true,
    this.onExpansionChanged,
    this.searchQuery,
    this.showSearchResults = false,
    this.onItemTap,
    this.loadingItemId,
    this.pluginsLoading = false,
  });

  @override
  State<BusinessSettingsCategorySection> createState() =>
      _BusinessSettingsCategorySectionState();
}

class _BusinessSettingsCategorySectionState
    extends State<BusinessSettingsCategorySection>
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
  void didUpdateWidget(BusinessSettingsCategorySection oldWidget) {
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

  bool get _isDangerCategory => widget.category.id == 'danger_zone';

  Widget _buildItemsGrid(
    BuildContext context,
    List<SettingsItem> items,
  ) {
    final cards = items.map((item) {
      final isDanger = _isDangerCategory || item.tags.contains('danger');
      return BusinessSettingsCard(
        item: item,
        isHighlighted: widget.showSearchResults &&
            widget.searchQuery != null &&
            widget.searchQuery!.isNotEmpty,
        isDanger: isDanger,
        isLoading: widget.loadingItemId == item.id,
        onTap: widget.onItemTap != null
            ? () => widget.onItemTap!(item)
            : (item.route.isEmpty ? null : () => context.push(item.route)),
      );
    }).toList();

    return BusinessSettingsLayout.buildTwoColumnGrid(
      context: context,
      children: cards,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final items = widget.category.items;
    final categoryColor =
        _isDangerCategory ? colorScheme.error : widget.category.color;

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

    final categorySubtitle = BusinessSettingsLocalizationHelper.getCategoryDescription(
      t,
      widget.category.description,
    );

    return Container(
      margin: EdgeInsets.only(bottom: sectionBottom),
      decoration: BoxDecoration(
        color: _isDangerCategory
            ? colorScheme.errorContainer.withValues(alpha: 0.15)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDangerCategory
              ? colorScheme.error.withValues(alpha: 0.35)
              : colorScheme.outline.withValues(alpha: 0.08),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: hzHeader, vertical: vtHeader),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(widget.category.icon, color: categoryColor, size: 20),
                    SizedBox(width: screenWideDesktop ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            BusinessSettingsLocalizationHelper.getCategoryTitle(
                              t,
                              widget.category.title,
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _isDangerCategory
                                  ? colorScheme.error
                                  : colorScheme.onSurface,
                              fontSize: 15,
                            ),
                          ),
                          if (categorySubtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              categorySubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.65),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (items.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${items.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: categoryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
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
                    padding: EdgeInsets.symmetric(horizontal: hzBody, vertical: vtBody),
                    child: widget.pluginsLoading &&
                            (widget.category.id == 'integrations' ||
                                widget.category.id == 'modules')
                        ? _buildPluginsLoading(context)
                        : items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    t.noSettingsInCategory,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              )
                            : _buildItemsGrid(context, items),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginsLoading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.of(context).businessSettingsPluginsLoadingHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}
