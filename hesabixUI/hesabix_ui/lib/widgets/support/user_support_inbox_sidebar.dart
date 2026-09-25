import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/support/user_support_tab_bar.dart';
import 'package:hesabix_ui/widgets/support/user_support_types.dart';

/// Narrow inbox column for master-detail support layout (list + chat).
class UserSupportInboxSidebar extends StatelessWidget {
  final AppLocalizations t;
  final TextEditingController searchController;
  final UserSupportTab activeTab;
  final int activeFilterCount;
  final ValueChanged<UserSupportTab> onTabChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onOpenFilters;
  final VoidCallback onCreateTicket;
  final VoidCallback? onOpenBilling;
  final Widget ticketList;

  const UserSupportInboxSidebar({
    super.key,
    required this.t,
    required this.searchController,
    required this.activeTab,
    required this.activeFilterCount,
    required this.onTabChanged,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onSearchSubmitted,
    required this.onOpenFilters,
    required this.onCreateTicket,
    this.onOpenBilling,
    required this.ticketList,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                Text(
                  t.supportTickets,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (onOpenBilling != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'اشتراک و صورتحساب',
                    onPressed: onOpenBilling,
                    icon: const Icon(Icons.card_membership_outlined, size: 20),
                  ),
                Badge(
                  isLabelVisible: activeFilterCount > 0,
                  label: Text('$activeFilterCount'),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'فیلترها',
                    onPressed: onOpenFilters,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: t.newTicket,
                  onPressed: onCreateTicket,
                  icon: const Icon(Icons.add_rounded, size: 22),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: SearchBar(
              controller: searchController,
              hintText: 'جست‌وجو…',
              hintStyle: WidgetStatePropertyAll(
                theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              leading: Icon(Icons.search_rounded, size: 18, color: scheme.onSurfaceVariant),
              trailing: [
                ListenableBuilder(
                  listenable: searchController,
                  builder: (context, _) {
                    if (searchController.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: onSearchClear,
                    );
                  },
                ),
              ],
              onChanged: onSearchChanged,
              onSubmitted: (_) => onSearchSubmitted(),
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(scheme.surface),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              constraints: const BoxConstraints(minHeight: 40),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: UserSupportTabBar(activeTab: activeTab, onChanged: onTabChanged),
          ),
          const SizedBox(height: 4),
          Expanded(child: ticketList),
        ],
      ),
    );
  }
}
