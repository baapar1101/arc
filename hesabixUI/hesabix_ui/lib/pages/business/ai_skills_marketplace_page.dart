import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/wallet_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';
import 'package:hesabix_ui/widgets/ai/ai_empty_state.dart';
import 'package:hesabix_ui/widgets/ai/ai_skill_marketplace_card.dart';
import 'package:hesabix_ui/widgets/ai/ai_skill_purchase_confirm_dialog.dart';

/// مارکت‌پلیس مهارت‌های AI
class AISkillsMarketplacePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const AISkillsMarketplacePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<AISkillsMarketplacePage> createState() => _AISkillsMarketplacePageState();
}

class _AISkillsMarketplacePageState extends State<AISkillsMarketplacePage>
    with SingleTickerProviderStateMixin {
  final AIService _aiService = AIService(ApiClient());
  final WalletService _walletService = WalletService(ApiClient());
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _marketItems = [];
  List<Map<String, dynamic>> _officialItems = [];
  List<Map<String, dynamic>> _anthropicItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _busy = true;
    });
    try {
      final idx = _tabController.index;
      if (idx == 0) {
        final raw = await _aiService.listSkillMarketplace(
          search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          isOfficial: false,
          businessId: widget.businessId,
        );
        final list = (raw['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        if (mounted) setState(() => _marketItems = list);
      } else if (idx == 1) {
        final raw = await _aiService.listSkillMarketplace(
          isOfficial: true,
          businessId: widget.businessId,
        );
        final list = (raw['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        if (mounted) setState(() => _officialItems = list);
      } else {
        final list = await _aiService.listAnthropicSkillCatalog();
        if (mounted) setState(() => _anthropicItems = list);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  String _priceLabel(Map<String, dynamic> item) {
    final price = item['price_amount'];
    if (price == null || (price is num && price <= 0)) return 'رایگان';
    if (item['is_purchased'] == true) return 'خریداری شده';
    return 'قیمت: $price';
  }

  Future<void> _installPackage(Map<String, dynamic> item) async {
    final id = item['id'];
    final packageId = id is int ? id : int.tryParse('$id');
    if (packageId == null) return;

    final price = item['price_amount'];
    final isPaid = price is num && price > 0;
    final alreadyOwned = item['is_purchased'] == true;

    if (isPaid && !alreadyOwned) {
      try {
        final wallet = await _walletService.getOverview(businessId: widget.businessId);
        final balance = (wallet['available_balance'] as num?)?.toDouble() ?? 0;
        final symbol = wallet['base_currency_symbol']?.toString() ??
            wallet['base_currency_code']?.toString() ??
            '';
        if (!mounted) return;
        final ok = await AISkillPurchaseConfirmDialog.show(
          context,
          skillTitle: item['title']?.toString() ?? '',
          price: price.toDouble(),
          currencySymbol: symbol,
          walletBalance: balance,
        );
        if (ok != true) return;
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: ErrorExtractor.forContext(e, context),
            isError: true,
          );
        }
        return;
      }
    }

    setState(() => _busy = true);
    try {
      await _aiService.installSkill(businessId: widget.businessId, packageId: packageId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت نصب شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installAnthropic(String skillId) async {
    setState(() => _busy = true);
    try {
      await _aiService.installAnthropicSkill(
        businessId: widget.businessId,
        anthropicSkillId: skillId,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت Anthropic نصب شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _packageCard(
    Map<String, dynamic> item, {
    required bool isOfficial,
    required VoidCallback onInstall,
  }) {
    final purchased = item['is_purchased'] == true;
    return AISkillMarketplaceCard(
      title: item['title']?.toString() ?? '',
      description: item['short_description']?.toString() ??
          item['description']?.toString() ??
          '',
      priceLabel: _priceLabel(item),
      isOfficial: isOfficial,
      isPurchased: purchased,
      busy: _busy,
      onInstall: purchased ? null : onInstall,
      leadingIcon: isOfficial ? Icons.verified_outlined : Icons.extension_outlined,
    );
  }

  Widget _buildPackageList(
    List<Map<String, dynamic>> items, {
    required bool isOfficial,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (items.isEmpty) {
      return AIEmptyState(
        icon: Icons.extension_off_outlined,
        title: emptyTitle,
        subtitle: emptySubtitle,
        action: OutlinedButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('بارگذاری دوباره'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final item in items)
          _packageCard(
            item,
            isOfficial: isOfficial,
            onInstall: () => _installPackage(item),
          ),
      ],
    );
  }

  Widget _buildAnthropicList() {
    if (_anthropicItems.isEmpty) {
      return const AIEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'مهارتی در کاتالوگ Anthropic نیست',
        subtitle: 'بعداً دوباره بررسی کنید یا از مارکت‌پلیس جامعه استفاده کنید.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final item in _anthropicItems)
          AISkillMarketplaceCard(
            title: item['title']?.toString() ??
                item['anthropic_skill_id']?.toString() ??
                '',
            description: item['description']?.toString() ?? '',
            priceLabel: 'رایگان',
            busy: _busy,
            leadingIcon: Icons.auto_awesome_outlined,
            onInstall: () {
              final sid = item['anthropic_skill_id']?.toString() ?? '';
              if (sid.isNotEmpty) _installAnthropic(sid);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مارکت‌پلیس مهارت‌های AI'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'جامعه'),
            Tab(text: 'حسابیکس'),
            Tab(text: 'Anthropic'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: AIChatDesign.pageBackground(theme, isDark: isDark),
        child: Column(
          children: [
            if (_tabController.index == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'جستجوی مهارت…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surface.withValues(alpha: 0.9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AIChatDesign.chipRadius),
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPackageList(
                          _marketItems,
                          isOfficial: false,
                          emptyTitle: 'مهارتی یافت نشد',
                          emptySubtitle:
                              'عبارت جستجو را تغییر دهید یا بعداً دوباره امتحان کنید.',
                        ),
                        _buildPackageList(
                          _officialItems,
                          isOfficial: true,
                          emptyTitle: 'مهارت رسمی یافت نشد',
                          emptySubtitle:
                              'مهارت‌های رسمی حسابیکس به‌زودی اینجا نمایش داده می‌شوند.',
                        ),
                        _buildAnthropicList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
