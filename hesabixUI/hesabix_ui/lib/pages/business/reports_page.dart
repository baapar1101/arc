import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
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
              title: 'گزارشات اشخاص',
              icon: Icons.people_outline,
              children: [
                _buildReportItem(
                  context,
                  title: 'لیست بدهکاران',
                  subtitle: 'نمایش اشخاص با مانده بدهکار',
                  icon: Icons.trending_down,
                  onTap: () => _showComingSoonDialog(context, 'لیست بدهکاران'),
                ),
                _buildReportItem(
                  context,
                  title: 'لیست بستانکاران',
                  subtitle: 'نمایش اشخاص با مانده بستانکار',
                  icon: Icons.trending_up,
                  onTap: () => _showComingSoonDialog(context, 'لیست بستانکاران'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش تراکنش‌های اشخاص',
                  subtitle: 'ریز دریافت‌ها و پرداخت‌ها به تفکیک شخص',
                  icon: Icons.receipt_long,
                  onTap: () => _showComingSoonDialog(context, 'گزارش تراکنش‌های اشخاص'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات کالا و خدمات',
              icon: Icons.inventory_2_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گردش کالا',
                  subtitle: 'ورود، خروج و مانده کالا به تفکیک بازه',
                  icon: Icons.sync_alt,
                  onTap: () => _showComingSoonDialog(context, 'گردش کالا'),
                ),
                _buildReportItem(
                  context,
                  title: 'کارتکس انبار',
                  subtitle: 'ریز گردش هر کالا (FIFO/LIFO/میانگین)',
                  icon: Icons.storage,
                  onTap: () => _showComingSoonDialog(context, 'کارتکس انبار'),
                ),
                _buildReportItem(
                  context,
                  title: 'فروش به تفکیک کالا',
                  subtitle: 'عملکرد فروش هر کالا در بازه زمانی',
                  icon: Icons.shopping_cart_checkout,
                  onTap: () => _showComingSoonDialog(context, 'فروش به تفکیک کالا'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات بانک و صندوق',
              icon: Icons.account_balance_wallet_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گردش حساب‌های بانکی',
                  subtitle: 'برداشت و واریز به تفکیک حساب',
                  icon: Icons.account_balance,
                  onTap: () => _showComingSoonDialog(context, 'گردش حساب‌های بانکی'),
                ),
                _buildReportItem(
                  context,
                  title: 'گردش صندوق و تنخواه',
                  subtitle: 'ریز ورود و خروج وجه نقد',
                  icon: Icons.savings,
                  onTap: () => _showComingSoonDialog(context, 'گردش صندوق و تنخواه'),
                ),
                _buildReportItem(
                  context,
                  title: 'چک‌ها',
                  subtitle: 'دریافتی، پرداختی، سررسیدها و وضعیت‌ها',
                  icon: Icons.payments_outlined,
                  onTap: () => _showComingSoonDialog(context, 'چک‌ها'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات فروش',
              icon: Icons.point_of_sale,
              children: [
                _buildReportItem(
                  context,
                  title: 'فروش روزانه',
                  subtitle: 'عملکرد فروش روزانه و روندها',
                  icon: Icons.today,
                  onTap: () => _showComingSoonDialog(context, 'فروش روزانه'),
                ),
                _buildReportItem(
                  context,
                  title: 'فروش ماهانه',
                  subtitle: 'مقایسه ماهانه و رشد فروش',
                  icon: Icons.calendar_month,
                  onTap: () => _showComingSoonDialog(context, 'فروش ماهانه'),
                ),
                _buildReportItem(
                  context,
                  title: 'مشتریان برتر',
                  subtitle: 'رتبه‌بندی بر اساس مبلغ یا تعداد',
                  icon: Icons.emoji_events_outlined,
                  onTap: () => _showComingSoonDialog(context, 'مشتریان برتر'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات خرید',
              icon: Icons.shopping_bag_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'خرید روزانه',
                  subtitle: 'عملکرد خرید روزانه و روندها',
                  icon: Icons.today,
                  onTap: () => _showComingSoonDialog(context, 'خرید روزانه'),
                ),
                _buildReportItem(
                  context,
                  title: 'تامین‌کنندگان برتر',
                  subtitle: 'رتبه‌بندی تامین‌کنندگان بر اساس خرید',
                  icon: Icons.handshake,
                  onTap: () => _showComingSoonDialog(context, 'تامین‌کنندگان برتر'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'گزارشات تولید',
              icon: Icons.factory_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گزارش مصرف مواد',
                  subtitle: 'مصرف مواد اولیه به ازای محصول',
                  icon: Icons.dataset_outlined,
                  onTap: () => _showComingSoonDialog(context, 'گزارش مصرف مواد'),
                ),
                _buildReportItem(
                  context,
                  title: 'گزارش تولیدات',
                  subtitle: 'میزان تولید و ضایعات',
                  icon: Icons.precision_manufacturing_outlined,
                  onTap: () => _showComingSoonDialog(context, 'گزارش تولیدات'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'حسابداری پایه',
              icon: Icons.calculate_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'تراز آزمایشی',
                  subtitle: 'تراز دو/چهار/شش/هشت ستونی',
                  icon: Icons.grid_on,
                  onTap: () => _showComingSoonDialog(context, 'تراز آزمایشی'),
                ),
                _buildReportItem(
                  context,
                  title: 'دفتر کل',
                  subtitle: 'گردش حساب‌ها در بازه زمانی',
                  icon: Icons.menu_book_outlined,
                  onTap: () => _showComingSoonDialog(context, 'دفتر کل'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSection(
              context,
              title: 'سود و زیان',
              icon: Icons.assessment_outlined,
              children: [
                _buildReportItem(
                  context,
                  title: 'گزارش سود و زیان دوره',
                  subtitle: 'درآمدها، هزینه‌ها و سود/زیان خالص',
                  icon: Icons.show_chart,
                  onTap: () => _showComingSoonDialog(context, 'گزارش سود و زیان دوره'),
                ),
                _buildReportItem(
                  context,
                  title: 'سود و زیان تجمیعی',
                  subtitle: 'مقایسه دوره‌ای و تجمیعی',
                  icon: Icons.query_stats,
                  onTap: () => _showComingSoonDialog(context, 'سود و زیان تجمیعی'),
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
        content: Text('این گزارش به‌زودی در دسترس خواهد بود.'),
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


