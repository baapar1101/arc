import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../widgets/permission/access_denied_page.dart';

class ReportsPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const ReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!authStore.canReadSection('reports')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              title: t.reportsGeneralSection,
              icon: Icons.assessment,
              children: [
                _buildReportItem(
                  context,
                  title: t.kardexDocuments,
                  subtitle: t.reportsKardexSubtitle,
                  icon: Icons.view_kanban,
                  onTap: () => context.go('/business/$businessId/reports/kardex'),
                ),
              ],
            ),

            const SizedBox(height: 24),
            _buildSection(
              context,
              title: t.reportsPeopleSection,
              icon: Icons.people_outline,
              children: [
                _buildReportItem(
                  context,
                  title: 'گزارش اقساط',
                  subtitle: 'وضعیت اقساط، سررسیدها و مانده',
                  icon: Icons.payments_outlined,
                  onTap: () => context.go('/business/$businessId/installments-report'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsDebtorsTitle,
                  subtitle: t.reportsDebtorsSubtitle,
                  icon: Icons.trending_down,
                  onTap: () => context.go('/business/$businessId/reports/debtors'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsCreditorsTitle,
                  subtitle: t.reportsCreditorsSubtitle,
                  icon: Icons.trending_up,
                  onTap: () => context.go('/business/$businessId/reports/creditors'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsPeopleTransactionsTitle,
                  subtitle: t.reportsPeopleTransactionsSubtitle,
                  icon: Icons.receipt_long,
                  onTap: () => context.go('/business/$businessId/reports/people-transactions'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsProductsSection,
              icon: Icons.inventory_2_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsItemMovementsTitle,
                  subtitle: t.reportsItemMovementsSubtitle,
                  icon: Icons.sync_alt,
                  onTap: () => context.go('/business/$businessId/reports/item-movements'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsInventoryKardexTitle,
                  subtitle: t.reportsInventoryKardexSubtitle,
                  icon: Icons.storage,
                  onTap: () => context.go('/business/$businessId/reports/inventory-kardex'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsSalesByProductTitle,
                  subtitle: t.reportsSalesByProductSubtitle,
                  icon: Icons.shopping_cart_checkout,
                  onTap: () => context.go('/business/$businessId/reports/sales-by-product'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsBankingSection,
              icon: Icons.account_balance_wallet_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsBankAccountsTurnoverTitle,
                  subtitle: t.reportsBankAccountsTurnoverSubtitle,
                  icon: Icons.account_balance,
                  onTap: () => _showComingSoonDialog(context, t.reportsBankAccountsTurnoverTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsCashPettyTurnoverTitle,
                  subtitle: t.reportsCashPettyTurnoverSubtitle,
                  icon: Icons.savings,
                  onTap: () => _showComingSoonDialog(context, t.reportsCashPettyTurnoverTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsChecksTitle,
                  subtitle: t.reportsChecksSubtitle,
                  icon: Icons.payments_outlined,
                  onTap: () => _showComingSoonDialog(context, t.reportsChecksTitle),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsSalesSection,
              icon: Icons.point_of_sale,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsDailySalesTitle,
                  subtitle: t.reportsDailySalesSubtitle,
                  icon: Icons.today,
                  onTap: () => _showComingSoonDialog(context, t.reportsDailySalesTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsMonthlySalesTitle,
                  subtitle: t.reportsMonthlySalesSubtitle,
                  icon: Icons.calendar_month,
                  onTap: () => _showComingSoonDialog(context, t.reportsMonthlySalesTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsTopCustomersTitle,
                  subtitle: t.reportsTopCustomersSubtitle,
                  icon: Icons.emoji_events_outlined,
                  onTap: () => _showComingSoonDialog(context, t.reportsTopCustomersTitle),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsPurchasesSection,
              icon: Icons.shopping_bag_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsDailyPurchasesTitle,
                  subtitle: t.reportsDailyPurchasesSubtitle,
                  icon: Icons.today,
                  onTap: () => _showComingSoonDialog(context, t.reportsDailyPurchasesTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsTopSuppliersTitle,
                  subtitle: t.reportsTopSuppliersSubtitle,
                  icon: Icons.handshake,
                  onTap: () => _showComingSoonDialog(context, t.reportsTopSuppliersTitle),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsProductionSection,
              icon: Icons.factory_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsMaterialsConsumptionTitle,
                  subtitle: t.reportsMaterialsConsumptionSubtitle,
                  icon: Icons.dataset_outlined,
                  onTap: () => _showComingSoonDialog(context, t.reportsMaterialsConsumptionTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsProductionTitle,
                  subtitle: t.reportsProductionSubtitle,
                  icon: Icons.precision_manufacturing_outlined,
                  onTap: () => _showComingSoonDialog(context, t.reportsProductionTitle),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsBasicAccountingSection,
              icon: Icons.calculate_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsTrialBalanceTitle,
                  subtitle: t.reportsTrialBalanceSubtitle,
                  icon: Icons.grid_on,
                  onTap: () => _showComingSoonDialog(context, t.reportsTrialBalanceTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsGeneralLedgerTitle,
                  subtitle: t.reportsGeneralLedgerSubtitle,
                  icon: Icons.menu_book_outlined,
                  onTap: () => _showComingSoonDialog(context, t.reportsGeneralLedgerTitle),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: t.reportsProfitLossSection,
              icon: Icons.assessment_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: t.reportsPnlPeriodTitle,
                  subtitle: t.reportsPnlPeriodSubtitle,
                  icon: Icons.show_chart,
                  onTap: () => _showComingSoonDialog(context, t.reportsPnlPeriodTitle),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsPnlCumulativeTitle,
                  subtitle: t.reportsPnlCumulativeSubtitle,
                  icon: Icons.query_stats,
                  onTap: () => _showComingSoonDialog(context, t.reportsPnlCumulativeTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildReportItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _showComingSoonDialog(BuildContext context, String title) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(t.reportsComingSoonMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }
}


