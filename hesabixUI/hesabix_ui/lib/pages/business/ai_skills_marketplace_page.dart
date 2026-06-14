import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/wallet_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
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
          price: (price as num).toDouble(),
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

  Widget _packageTile(Map<String, dynamic> item, {required VoidCallback onInstall}) {
    return ListTile(
      title: Text(item['title']?.toString() ?? ''),
      subtitle: Text(
        '${item['short_description'] ?? item['description'] ?? ''}\n${_priceLabel(item)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: _busy ? null : onInstall,
        child: const Text('نصب'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      ),
      body: Column(
        children: [
          if (_tabController.index == 0)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'جستجو…',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _marketItems.isEmpty
                          ? const Center(child: Text('مهارتی یافت نشد'))
                          : ListView.separated(
                              itemCount: _marketItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = _marketItems[i];
                                final id = item['id'];
                                final packageId = id is int ? id : int.tryParse('$id');
                                if (packageId == null) return const SizedBox.shrink();
                                return _packageTile(
                                  item,
                                  onInstall: () => _installPackage(item),
                                );
                              },
                            ),
                      _officialItems.isEmpty
                          ? const Center(child: Text('مهارت رسمی یافت نشد'))
                          : ListView.separated(
                              itemCount: _officialItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = _officialItems[i];
                                final id = item['id'];
                                final packageId = id is int ? id : int.tryParse('$id');
                                if (packageId == null) return const SizedBox.shrink();
                                return _packageTile(
                                  item,
                                  onInstall: () => _installPackage(item),
                                );
                              },
                            ),
                      ListView.separated(
                        itemCount: _anthropicItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = _anthropicItems[i];
                          final sid = item['anthropic_skill_id']?.toString() ?? '';
                          return ListTile(
                            leading: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                            title: Text(item['title']?.toString() ?? sid),
                            subtitle: Text(item['description']?.toString() ?? ''),
                            trailing: FilledButton(
                              onPressed: _busy || sid.isEmpty ? null : () => _installAnthropic(sid),
                              child: const Text('نصب'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
