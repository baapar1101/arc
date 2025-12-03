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
                  title: t.reportsInventoryStockTitle,
                  subtitle: t.reportsInventoryStockSubtitle,
                  icon: Icons.inventory_2_outlined,
                  onTap: () => context.go('/business/$businessId/reports/inventory-stock'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش انبار گردانی',
                  subtitle: 'تاریخچه انبار گردانی‌ها و حواله‌های تعدیل',
                  icon: Icons.inventory,
                  onTap: () => context.go('/business/$businessId/reports/stock-count'),
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
              title: 'گزارشات انبار',
              icon: Icons.warehouse_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گزارش خلاصه حواله‌های انبار',
                  subtitle: 'خلاصه حواله‌ها به تفکیک نوع با آمار ورود و خروج',
                  icon: Icons.summarize,
                  onTap: () => context.go('/business/$businessId/reports/warehouse-documents-summary'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش کالاهای کم‌گردش',
                  subtitle: 'کالاهایی که در بازه زمانی مشخص شده هیچ حرکتی نداشته‌اند',
                  icon: Icons.trending_down,
                  onTap: () => context.go('/business/$businessId/reports/slow-moving-items'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش کالاهای با موجودی بحرانی',
                  subtitle: 'کالاهایی که موجودی آن‌ها کمتر از حد تعیین شده است',
                  icon: Icons.warning_amber,
                  onTap: () => context.go('/business/$businessId/reports/critical-stock'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش انتقالات بین انبارها',
                  subtitle: 'جزئیات انتقالات بین انبارها',
                  icon: Icons.swap_horiz,
                  onTap: () => context.go('/business/$businessId/reports/inter-warehouse-transfers'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش حواله‌های تعدیل',
                  subtitle: 'تحلیل حواله‌های تعدیل و تفاوت‌های موجودی',
                  icon: Icons.tune,
                  onTap: () => context.go('/business/$businessId/reports/adjustment-documents'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش عملکرد انبارها',
                  subtitle: 'مقایسه عملکرد انبارها',
                  icon: Icons.analytics,
                  onTap: () => context.go('/business/$businessId/reports/warehouse-performance'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش تاریخچه حرکات یک کالا',
                  subtitle: 'تاریخچه کامل حرکات یک کالا در تمام انبارها',
                  icon: Icons.history,
                  onTap: () => context.go('/business/$businessId/reports/product-movement-history'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش ارزش موجودی انبار',
                  subtitle: 'ارزش ریالی موجودی انبارها',
                  icon: Icons.attach_money,
                  onTap: () => context.go('/business/$businessId/reports/inventory-valuation'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش حواله‌های در انتظار تایید',
                  subtitle: 'حواله‌های draft یا در انتظار تایید',
                  icon: Icons.pending_actions,
                  onTap: () => context.go('/business/$businessId/reports/pending-documents'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش گردش موجودی',
                  subtitle: 'نرخ گردش موجودی کالاها',
                  icon: Icons.autorenew,
                  onTap: () => context.go('/business/$businessId/reports/inventory-turnover'),
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
                  onTap: () => context.go('/business/$businessId/reports/bank-accounts-turnover'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsCashPettyTurnoverTitle,
                  subtitle: t.reportsCashPettyTurnoverSubtitle,
                  icon: Icons.savings,
                  onTap: () => context.go('/business/$businessId/reports/cash-petty-turnover'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsChecksTitle,
                  subtitle: t.reportsChecksSubtitle,
                  icon: Icons.payments_outlined,
                  onTap: () => context.go('/business/$businessId/checks'),
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
                  onTap: () => context.go('/business/$businessId/reports/daily-sales'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsMonthlySalesTitle,
                  subtitle: t.reportsMonthlySalesSubtitle,
                  icon: Icons.calendar_month,
                  onTap: () => context.go('/business/$businessId/reports/monthly-sales'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsTopCustomersTitle,
                  subtitle: t.reportsTopCustomersSubtitle,
                  icon: Icons.emoji_events_outlined,
                  onTap: () => context.go('/business/$businessId/reports/top-customers'),
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
                  onTap: () => context.go('/business/$businessId/reports/daily-purchases'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsTopSuppliersTitle,
                  subtitle: t.reportsTopSuppliersSubtitle,
                  icon: Icons.handshake,
                  onTap: () => context.go('/business/$businessId/reports/top-suppliers'),
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
                  onTap: () => context.go('/business/$businessId/reports/materials-consumption'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsProductionTitle,
                  subtitle: t.reportsProductionSubtitle,
                  icon: Icons.precision_manufacturing_outlined,
                  onTap: () => context.go('/business/$businessId/reports/production'),
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
                  onTap: () => context.go('/business/$businessId/reports/trial-balance'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsGeneralLedgerTitle,
                  subtitle: t.reportsGeneralLedgerSubtitle,
                  icon: Icons.menu_book_outlined,
                  onTap: () => context.go('/business/$businessId/reports/general-ledger'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsJournalLedgerTitle,
                  subtitle: t.reportsJournalLedgerSubtitle,
                  icon: Icons.book_outlined,
                  onTap: () => context.go('/business/$businessId/reports/journal-ledger'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش مرور حساب‌ها',
                  subtitle: 'ساختار درختی حساب‌ها با مانده‌ها و جزئیات تراکنش‌ها',
                  icon: Icons.account_tree,
                  onTap: () => context.go('/business/$businessId/reports/accounts-review'),
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
                  onTap: () => context.go('/business/$businessId/reports/pnl-period'),
                ),
                _buildReportItem(
                  context,
                  title: t.reportsPnlCumulativeTitle,
                  subtitle: t.reportsPnlCumulativeSubtitle,
                  icon: Icons.query_stats,
                  onTap: () => context.go('/business/$businessId/reports/pnl-cumulative'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات سیستم',
              icon: Icons.assignment_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گزارش فعالیت‌های کاربران',
                  subtitle: 'مشاهده تاریخچه فعالیت‌های کاربران در سیستم',
                  icon: Icons.history,
                  onTap: () => context.go('/business/$businessId/reports/activity-logs'),
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
}


