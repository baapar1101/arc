import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/basalam_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

class BasalamIntegrationPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const BasalamIntegrationPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<BasalamIntegrationPage> createState() => _BasalamIntegrationPageState();
}

class _BasalamIntegrationPageState extends State<BasalamIntegrationPage> {
  final BasalamIntegrationService _svc = BasalamIntegrationService();
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;
  bool _syncingProducts = false;
  bool _publishingProducts = false;
  bool _pullingProducts = false;
  bool _pushingIncrementalProducts = false;
  bool _retryingPublishQueue = false;
  bool _loadingConflicts = false;
  bool _clearingConflicts = false;
  bool _resolvingConflicts = false;
  bool _syncingPayments = false;
  bool _syncingInboundChats = false;
  bool _sendingChatReply = false;

  final _apiKeyCtl = TextEditingController();
  final _apiRefreshTokenCtl = TextEditingController();
  final _baseUrlCtl = TextEditingController();
  final _defaultVendorIdCtl = TextEditingController();
  final _defaultCategoryIdCtl = TextEditingController();
  final _defaultBasalamStockCtl = TextEditingController(text: '1');
  final _pullPageCtl = TextEditingController(text: '1');
  final _pullPerPageCtl = TextEditingController(text: '50');
  final _pushSinceMinutesCtl = TextEditingController(text: '120');
  final _pushLimitCtl = TextEditingController(text: '50');
  final _retryLimitCtl = TextEditingController(text: '20');
  final _resolveLimitCtl = TextEditingController(text: '20');
  final _webhookSecretCtl = TextEditingController();
  final _defaultTagCtl = TextEditingController();
  final _sampleOrdersCtl = TextEditingController(
    text: '[{"order_id":"demo-1","status":"paid"}]',
  );
  final _sampleProductsCtl = TextEditingController(
    text: '[{"id":"p-1","title":"کالای نمونه","price":120000}]',
  );
  final _samplePublishProductsCtl = TextEditingController(
    text: '[{"local_product_id":1,"name":"Sample Product","primary_price":120000,"stock":5}]',
  );
  final _sampleInboundChatCtl = TextEditingController(
    text:
        '{"chat_id":"1001","customer":{"name":"Demo User","mobile":"09120000000"},"messages":[{"id":"m-1","body":"سلام از باسلام"}]}',
  );
  final _replyConversationIdCtl = TextEditingController();
  final _replyChatIdCtl = TextEditingController();
  final _replyBodyCtl = TextEditingController();

  bool _enabled = false;
  bool _webhookEnabled = false;
  bool _chatEnabled = true;
  bool _orderSyncEnabled = true;
  bool _productSyncEnabled = true;
  bool _createInvoiceOnSync = true;
  String _invoiceTypeOnSync = 'invoice_sales';
  String _personMode = 'match_or_create';
  String _productMode = 'match_or_create';
  String _paymentMode = 'manual_review';
  String _priceConflictStrategy = 'local_wins';
  String _stockConflictStrategy = 'local_wins';
  String _variantStrategy = 'manual_review';
  String? _lastWebhookEventType;
  String? _lastWebhookEventAt;
  int _productConflictCount = 0;
  List<Map<String, dynamic>> _productConflicts = const [];
  Set<String> _selectedConflictIds = <String>{};
  bool _productConflictsHasMore = false;
  int _productConflictsOffset = 0;
  static const int _productConflictsPageSize = 25;
  String _conflictTypeFilter = 'all';
  String _conflictDirectionFilter = 'all';
  String _conflictSortBy = 'created_at';
  String _conflictSortDir = 'desc';
  final _conflictSearchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyCtl.dispose();
    _apiRefreshTokenCtl.dispose();
    _baseUrlCtl.dispose();
    _defaultVendorIdCtl.dispose();
    _defaultCategoryIdCtl.dispose();
    _defaultBasalamStockCtl.dispose();
    _pullPageCtl.dispose();
    _pullPerPageCtl.dispose();
    _pushSinceMinutesCtl.dispose();
    _pushLimitCtl.dispose();
    _retryLimitCtl.dispose();
    _resolveLimitCtl.dispose();
    _webhookSecretCtl.dispose();
    _defaultTagCtl.dispose();
    _sampleOrdersCtl.dispose();
    _sampleProductsCtl.dispose();
    _samplePublishProductsCtl.dispose();
    _sampleInboundChatCtl.dispose();
    _replyConversationIdCtl.dispose();
    _replyChatIdCtl.dispose();
    _replyBodyCtl.dispose();
    _conflictSearchCtl.dispose();
    super.dispose();
  }

  String _title(AppLocalizations t) =>
      t.localeName.startsWith('fa') ? 'اتصال باسلام' : 'Basalam Integration';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _svc.getSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _enabled = d['enabled'] == true;
        _webhookEnabled = d['webhook_enabled'] == true;
        _chatEnabled = d['chat_enabled'] == true;
        _orderSyncEnabled = d['order_sync_enabled'] == true;
        _productSyncEnabled = d['product_sync_enabled'] == true;
        _createInvoiceOnSync = d['create_sales_invoice_on_sync'] != false;
        _invoiceTypeOnSync = (d['invoice_type_on_sync'] ?? 'invoice_sales')
            .toString();
        _personMode = (d['auto_create_person_mode'] ?? 'match_or_create')
            .toString();
        _productMode = (d['auto_create_product_mode'] ?? 'match_or_create')
            .toString();
        _paymentMode = (d['payment_register_mode'] ?? 'manual_review')
            .toString();
        _priceConflictStrategy =
            (d['product_conflict_price_strategy'] ?? 'local_wins').toString();
        _stockConflictStrategy =
            (d['product_conflict_stock_strategy'] ?? 'local_wins').toString();
        _variantStrategy =
            (d['product_variant_strategy'] ?? 'manual_review').toString();
        _apiKeyCtl.text = (d['api_key'] ?? '').toString();
        _apiRefreshTokenCtl.text = (d['api_refresh_token'] ?? '').toString();
        _baseUrlCtl.text = (d['api_base_url'] ?? 'https://api.basalam.com')
            .toString();
        _defaultVendorIdCtl.text = (d['default_basalam_vendor_id'] ?? '')
            .toString();
        _defaultCategoryIdCtl.text = (d['default_basalam_category_id'] ?? '')
            .toString();
        _defaultBasalamStockCtl.text = (d['default_basalam_stock'] ?? 1)
            .toString();
        _webhookSecretCtl.text = (d['webhook_secret'] ?? '').toString();
        _defaultTagCtl.text = (d['default_order_tag'] ?? 'basalam').toString();
        _lastWebhookEventType = d['last_webhook_event_type']?.toString();
        _lastWebhookEventAt = d['last_webhook_event_at']?.toString();
      });
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'enabled': _enabled,
          'api_key': _apiKeyCtl.text.trim(),
          'api_refresh_token': _apiRefreshTokenCtl.text.trim(),
          'api_base_url': _baseUrlCtl.text.trim(),
          'default_basalam_vendor_id': int.tryParse(
            _defaultVendorIdCtl.text.trim(),
          ),
          'default_basalam_category_id': int.tryParse(
            _defaultCategoryIdCtl.text.trim(),
          ),
          'default_basalam_stock':
              int.tryParse(_defaultBasalamStockCtl.text.trim()) ?? 1,
          'webhook_secret': _webhookSecretCtl.text.trim(),
          'webhook_enabled': _webhookEnabled,
          'chat_enabled': _chatEnabled,
          'order_sync_enabled': _orderSyncEnabled,
          'product_sync_enabled': _productSyncEnabled,
          'create_sales_invoice_on_sync': _createInvoiceOnSync,
          'invoice_type_on_sync': _invoiceTypeOnSync,
          'auto_create_person_mode': _personMode,
          'auto_create_product_mode': _productMode,
          'default_order_tag': _defaultTagCtl.text.trim(),
          'payment_register_mode': _paymentMode,
          'product_conflict_price_strategy': _priceConflictStrategy,
          'product_conflict_stock_strategy': _stockConflictStrategy,
          'product_variant_strategy': _variantStrategy,
        },
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'تنظیمات باسلام ذخیره شد'
            : 'Basalam settings saved',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadProductConflicts() async {
    if (!mounted) return;
    try {
      await _applyConflictFilters(offset: _productConflictsOffset);
    } catch (_) {
      // silent: conflict count is supplementary info
    }
  }

  Future<void> _clearProductConflicts() async {
    setState(() => _clearingConflicts = true);
    try {
      await _svc.clearProductConflicts(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _productConflictCount = 0;
        _productConflicts = const [];
        _productConflictsHasMore = false;
        _productConflictsOffset = 0;
        _selectedConflictIds = <String>{};
      });
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'صف تضادها پاک شد'
            : 'Conflict queue cleared',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingConflicts = false);
    }
  }

  Future<void> _resolveProductConflicts(
    String resolution, {
    List<String>? conflictIds,
  }) async {
    setState(() => _resolvingConflicts = true);
    try {
      final result = await _svc.resolveProductConflicts(
        businessId: widget.businessId,
        resolution: resolution,
        limit: int.tryParse(_resolveLimitCtl.text.trim()) ?? 20,
        vendorId: int.tryParse(_defaultVendorIdCtl.text.trim()),
        conflictIds: conflictIds ??
            (_selectedConflictIds.isEmpty
                ? null
                : _selectedConflictIds.toList()),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'حل تضاد انجام شد: ${result['resolved'] ?? 0}'
            : 'Conflict resolution done: ${result['resolved'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingConflicts = false);
    }
  }

  void _toggleConflictSelection(String conflictId, bool selected) {
    setState(() {
      if (selected) {
        _selectedConflictIds.add(conflictId);
      } else {
        _selectedConflictIds.remove(conflictId);
      }
    });
  }

  void _toggleSelectAllConflicts(bool selectAll) {
    final ids = _productConflicts
        .map((e) => e['conflict_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    setState(() {
      _selectedConflictIds = selectAll ? ids : <String>{};
    });
  }

  Future<void> _showConflictDetailsDialog(Map<String, dynamic> item) async {
    final isFa = AppLocalizations.of(context).localeName.startsWith('fa');
    final conflictId = item['conflict_id']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isFa ? 'جزئیات تضاد' : 'Conflict details'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(item),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isFa ? 'بستن' : 'Close'),
            ),
            FilledButton.tonal(
              onPressed: conflictId.isEmpty
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await _resolveProductConflicts(
                        'local_wins',
                        conflictIds: [conflictId],
                      );
                    },
              child: Text(isFa ? 'local_wins' : 'local_wins'),
            ),
            FilledButton.tonal(
              onPressed: conflictId.isEmpty
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await _resolveProductConflicts(
                        'remote_wins',
                        conflictIds: [conflictId],
                      );
                    },
              child: Text(isFa ? 'remote_wins' : 'remote_wins'),
            ),
            FilledButton.tonal(
              onPressed: conflictId.isEmpty
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await _resolveProductConflicts(
                        'discard',
                        conflictIds: [conflictId],
                      );
                    },
              child: Text(isFa ? 'discard' : 'discard'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyConflictFilters({int? offset}) async {
    if (offset != null) {
      _productConflictsOffset = offset;
    }
    setState(() => _loadingConflicts = true);
    try {
      final result = await _svc.getProductConflicts(
        businessId: widget.businessId,
        conflictType: _conflictTypeFilter == 'all' ? null : _conflictTypeFilter,
        direction: _conflictDirectionFilter == 'all'
            ? null
            : _conflictDirectionFilter,
        search: _conflictSearchCtl.text,
        sortBy: _conflictSortBy,
        sortDir: _conflictSortDir,
        limit: _productConflictsPageSize,
        offset: _productConflictsOffset,
      );
      if (!mounted) return;
      final total = result['total'];
      final count = total is int ? total : (total is num ? total.toInt() : 0);
      final rawItems = result['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final availableIds = items
          .map((e) => e['conflict_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      setState(() {
        _productConflictCount = count;
        _productConflicts = items;
        _productConflictsHasMore = result['has_more'] == true;
        _selectedConflictIds = _selectedConflictIds
            .where(availableIds.contains)
            .toSet();
      });
    } finally {
      if (mounted) setState(() => _loadingConflicts = false);
    }
  }

  Future<void> _manualSync() async {
    setState(() => _syncing = true);
    try {
      final parsed = jsonDecode(_sampleOrdersCtl.text);
      if (parsed is! List) {
        throw const FormatException('orders must be list');
      }
      final orders = parsed
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final result = await _svc.manualSyncOrders(
        businessId: widget.businessId,
        orders: orders,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'سینک دستی انجام شد: ${result['processed_orders'] ?? 0}'
            : 'Manual sync done: ${result['processed_orders'] ?? 0}',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncPayments() async {
    setState(() => _syncingPayments = true);
    try {
      final result = await _svc.syncUnverifiedPayments(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final synced = result['synced'] ?? 0;
      final processed = result['processed'] ?? 0;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'همگام‌سازی پرداخت انجام شد: $synced از $processed'
            : 'Payment sync done: $synced of $processed',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingPayments = false);
    }
  }

  Future<void> _manualProductSync() async {
    setState(() => _syncingProducts = true);
    try {
      final parsed = jsonDecode(_sampleProductsCtl.text);
      if (parsed is! List) {
        throw const FormatException('products must be list');
      }
      final products = parsed
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final result = await _svc.manualSyncProducts(
        businessId: widget.businessId,
        products: products,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'سینک کالا انجام شد: ${result['synced_products'] ?? 0}'
            : 'Product sync done: ${result['synced_products'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingProducts = false);
    }
  }

  Future<void> _publishProducts() async {
    setState(() => _publishingProducts = true);
    try {
      final parsed = jsonDecode(_samplePublishProductsCtl.text);
      if (parsed is! List) {
        throw const FormatException('products must be list');
      }
      final products = parsed
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final result = await _svc.publishProducts(
        businessId: widget.businessId,
        products: products,
        vendorId: int.tryParse(_defaultVendorIdCtl.text.trim()),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'انتشار کالا انجام شد: ${result['published_products'] ?? 0}'
            : 'Product publish done: ${result['published_products'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _publishingProducts = false);
    }
  }

  Future<void> _pullProducts() async {
    setState(() => _pullingProducts = true);
    try {
      final result = await _svc.pullProducts(
        businessId: widget.businessId,
        page: int.tryParse(_pullPageCtl.text.trim()) ?? 1,
        perPage: int.tryParse(_pullPerPageCtl.text.trim()) ?? 50,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'واکشی و سینک کالا انجام شد: ${result['synced_products'] ?? 0}'
            : 'Pull+sync products done: ${result['synced_products'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _pullingProducts = false);
    }
  }

  Future<void> _pushIncrementalProducts() async {
    setState(() => _pushingIncrementalProducts = true);
    try {
      final result = await _svc.pushProductsIncremental(
        businessId: widget.businessId,
        sinceMinutes: int.tryParse(_pushSinceMinutesCtl.text.trim()) ?? 120,
        limit: int.tryParse(_pushLimitCtl.text.trim()) ?? 50,
        vendorId: int.tryParse(_defaultVendorIdCtl.text.trim()),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'Push افزایشی انجام شد: ${result['published_products'] ?? 0}'
            : 'Incremental push done: ${result['published_products'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _pushingIncrementalProducts = false);
    }
  }

  Future<void> _retryPublishQueue() async {
    setState(() => _retryingPublishQueue = true);
    try {
      final result = await _svc.retryProductPublishQueue(
        businessId: widget.businessId,
        limit: int.tryParse(_retryLimitCtl.text.trim()) ?? 20,
        vendorId: int.tryParse(_defaultVendorIdCtl.text.trim()),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'Retry انجام شد: ${result['published_products'] ?? 0}'
            : 'Retry queue done: ${result['published_products'] ?? 0}',
      );
      await _loadProductConflicts();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _retryingPublishQueue = false);
    }
  }

  Future<void> _syncInboundChats() async {
    setState(() => _syncingInboundChats = true);
    try {
      final parsed = jsonDecode(_sampleInboundChatCtl.text);
      if (parsed is! Map) {
        throw const FormatException('chat payload must be object');
      }
      final result = await _svc.syncInboundChats(
        businessId: widget.businessId,
        payload: Map<String, dynamic>.from(parsed),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'سینک چت انجام شد: ${result['processed_messages'] ?? 0}'
            : 'Inbound chat synced: ${result['processed_messages'] ?? 0}',
      );
      final convId = result['crm_conversation_id']?.toString() ?? '';
      if (convId.isNotEmpty) {
        _replyConversationIdCtl.text = convId;
      }
      final chatId = result['chat_id']?.toString() ?? '';
      if (chatId.isNotEmpty) {
        _replyChatIdCtl.text = chatId;
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingInboundChats = false);
    }
  }

  Future<void> _sendChatReply() async {
    setState(() => _sendingChatReply = true);
    try {
      final convId = int.parse(_replyConversationIdCtl.text.trim());
      final result = await _svc.sendChatReply(
        businessId: widget.businessId,
        conversationId: convId,
        body: _replyBodyCtl.text.trim(),
        chatId: _replyChatIdCtl.text.trim().isEmpty
            ? null
            : _replyChatIdCtl.text.trim(),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).localeName.startsWith('fa')
            ? 'پاسخ ارسال شد (Chat: ${result['chat_id'] ?? '-'})'
            : 'Reply sent (Chat: ${result['chat_id'] ?? '-'})',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingChatReply = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isFa = t.localeName.startsWith('fa');
    final canView =
        widget.authStore.hasBusinessPermission('basalam', 'view') ||
        widget.authStore.currentBusiness?.isOwner == true;
    final canManage =
        widget.authStore.hasBusinessPermission('basalam', 'manage') ||
        widget.authStore.currentBusiness?.isOwner == true;
    final canSync =
        widget.authStore.hasBusinessPermission('basalam', 'sync') || canManage;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_title(t)),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(child: Text(t.accessDenied)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(t)),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: _enabled,
                  onChanged: canManage
                      ? (v) => setState(() => _enabled = v)
                      : null,
                  title: Text(
                    isFa
                        ? 'فعال‌سازی اتصال باسلام'
                        : 'Enable Basalam integration',
                  ),
                ),
                TextField(
                  controller: _apiKeyCtl,
                  enabled: canManage,
                  decoration: InputDecoration(
                    labelText: isFa ? 'API Key باسلام' : 'Basalam API key',
                  ),
                ),
                TextField(
                  controller: _apiRefreshTokenCtl,
                  enabled: canManage,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'Refresh Token باسلام (اختیاری)'
                        : 'Basalam refresh token (optional)',
                  ),
                ),
                TextField(
                  controller: _baseUrlCtl,
                  enabled: canManage,
                  decoration: InputDecoration(
                    labelText: isFa ? 'آدرس پایه API' : 'API base URL',
                  ),
                ),
                TextField(
                  controller: _defaultVendorIdCtl,
                  enabled: canManage,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'Vendor ID پیش‌فرض باسلام'
                        : 'Default Basalam vendor ID',
                  ),
                ),
                TextField(
                  controller: _defaultCategoryIdCtl,
                  enabled: canManage,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'Category ID پیش‌فرض باسلام'
                        : 'Default Basalam category ID',
                  ),
                ),
                TextField(
                  controller: _defaultBasalamStockCtl,
                  enabled: canManage,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'موجودی پیش‌فرض انتشار'
                        : 'Default publish stock',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _webhookEnabled,
                  onChanged: canManage
                      ? (v) => setState(() => _webhookEnabled = v)
                      : null,
                  title: Text(isFa ? 'فعال‌سازی وب‌هوک' : 'Enable webhook'),
                ),
                TextField(
                  controller: _webhookSecretCtl,
                  enabled: canManage,
                  decoration: InputDecoration(
                    labelText: isFa ? 'Webhook Secret' : 'Webhook secret',
                  ),
                ),
                SwitchListTile(
                  value: _chatEnabled,
                  onChanged: canManage
                      ? (v) => setState(() => _chatEnabled = v)
                      : null,
                  title: Text(isFa ? 'فعال‌سازی چت' : 'Enable chat bridge'),
                ),
                SwitchListTile(
                  value: _orderSyncEnabled,
                  onChanged: canManage
                      ? (v) => setState(() => _orderSyncEnabled = v)
                      : null,
                  title: Text(
                    isFa ? 'فعال‌سازی سینک سفارش' : 'Enable order sync',
                  ),
                ),
                SwitchListTile(
                  value: _productSyncEnabled,
                  onChanged: canManage
                      ? (v) => setState(() => _productSyncEnabled = v)
                      : null,
                  title: Text(
                    isFa ? 'فعال‌سازی سینک کالا' : 'Enable product sync',
                  ),
                ),
                SwitchListTile(
                  value: _createInvoiceOnSync,
                  onChanged: canManage
                      ? (v) => setState(() => _createInvoiceOnSync = v)
                      : null,
                  title: Text(
                    isFa
                        ? 'ایجاد فاکتور هنگام سینک سفارش'
                        : 'Create invoice on order sync',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: _invoiceTypeOnSync,
                  onChanged: canManage
                      ? (v) => setState(
                          () => _invoiceTypeOnSync = v ?? _invoiceTypeOnSync,
                        )
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa ? 'نوع فاکتور سینک' : 'Sync invoice type',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'invoice_sales',
                      child: Text('invoice_sales'),
                    ),
                    DropdownMenuItem(
                      value: 'invoice_sales_return',
                      child: Text('invoice_sales_return'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _personMode,
                  onChanged: canManage
                      ? (v) => setState(() => _personMode = v ?? _personMode)
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'حالت تطبیق/ایجاد شخص'
                        : 'Person matching mode',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'match_only',
                      child: Text('match_only'),
                    ),
                    DropdownMenuItem(
                      value: 'create_only',
                      child: Text('create_only'),
                    ),
                    DropdownMenuItem(
                      value: 'match_or_create',
                      child: Text('match_or_create'),
                    ),
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _productMode,
                  onChanged: canManage
                      ? (v) => setState(() => _productMode = v ?? _productMode)
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'حالت تطبیق/ایجاد کالا'
                        : 'Product matching mode',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'match_only',
                      child: Text('match_only'),
                    ),
                    DropdownMenuItem(
                      value: 'create_only',
                      child: Text('create_only'),
                    ),
                    DropdownMenuItem(
                      value: 'match_or_create',
                      child: Text('match_or_create'),
                    ),
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _paymentMode,
                  onChanged: canManage
                      ? (v) => setState(() => _paymentMode = v ?? _paymentMode)
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'حالت ثبت سند پرداخت'
                        : 'Payment accounting mode',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                    DropdownMenuItem(
                      value: 'auto_bank',
                      child: Text('auto_bank'),
                    ),
                    DropdownMenuItem(
                      value: 'auto_cash',
                      child: Text('auto_cash'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _priceConflictStrategy,
                  onChanged: canManage
                      ? (v) => setState(
                            () =>
                                _priceConflictStrategy = v ?? _priceConflictStrategy,
                          )
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'استراتژی تضاد قیمت'
                        : 'Price conflict strategy',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'local_wins',
                      child: Text('local_wins'),
                    ),
                    DropdownMenuItem(
                      value: 'remote_wins',
                      child: Text('remote_wins'),
                    ),
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _stockConflictStrategy,
                  onChanged: canManage
                      ? (v) => setState(
                            () =>
                                _stockConflictStrategy = v ?? _stockConflictStrategy,
                          )
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'استراتژی تضاد موجودی'
                        : 'Stock conflict strategy',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'local_wins',
                      child: Text('local_wins'),
                    ),
                    DropdownMenuItem(
                      value: 'remote_wins',
                      child: Text('remote_wins'),
                    ),
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _variantStrategy,
                  onChanged: canManage
                      ? (v) => setState(
                            () => _variantStrategy = v ?? _variantStrategy,
                          )
                      : null,
                  decoration: InputDecoration(
                    labelText: isFa ? 'استراتژی واریانت' : 'Variant strategy',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'manual_review',
                      child: Text('manual_review'),
                    ),
                    DropdownMenuItem(
                      value: 'local_wins',
                      child: Text('local_wins'),
                    ),
                    DropdownMenuItem(
                      value: 'remote_wins',
                      child: Text('remote_wins'),
                    ),
                  ],
                ),
                TextField(
                  controller: _defaultTagCtl,
                  enabled: canManage,
                  decoration: InputDecoration(
                    labelText: isFa ? 'تگ پیش‌فرض سفارش' : 'Default order tag',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canManage && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(isFa ? 'ذخیره تنظیمات' : 'Save settings'),
                ),
                const Divider(height: 28),
                Text(
                  isFa ? 'وب‌هوک آخرین رویداد' : 'Latest webhook event',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${isFa ? 'نوع' : 'Type'}: ${_lastWebhookEventType ?? '-'}',
                ),
                Text(
                  '${isFa ? 'زمان' : 'Time'}: ${_lastWebhookEventAt ?? '-'}',
                ),
                const SizedBox(height: 8),
                Text(
                  '${isFa ? 'تضادهای محصول' : 'Product conflicts'}: ${_loadingConflicts ? '...' : _productConflictCount}',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _conflictTypeFilter,
                        onChanged: (v) async {
                          setState(() => _conflictTypeFilter = v ?? 'all');
                          _productConflictsOffset = 0;
                          await _applyConflictFilters(offset: 0);
                        },
                        decoration: InputDecoration(
                          labelText: isFa ? 'نوع تضاد' : 'Conflict type',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('all')),
                          DropdownMenuItem(
                            value: 'field_conflict',
                            child: Text('field_conflict'),
                          ),
                          DropdownMenuItem(
                            value: 'variant_conflict',
                            child: Text('variant_conflict'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _conflictDirectionFilter,
                        onChanged: (v) async {
                          setState(
                            () => _conflictDirectionFilter = v ?? 'all',
                          );
                          _productConflictsOffset = 0;
                          await _applyConflictFilters(offset: 0);
                        },
                        decoration: InputDecoration(
                          labelText: isFa ? 'جهت' : 'Direction',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('all')),
                          DropdownMenuItem(value: 'pull', child: Text('pull')),
                          DropdownMenuItem(value: 'push', child: Text('push')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _conflictSortBy,
                        onChanged: (v) async {
                          setState(() => _conflictSortBy = v ?? 'created_at');
                          _productConflictsOffset = 0;
                          await _applyConflictFilters(offset: 0);
                        },
                        decoration: InputDecoration(
                          labelText: isFa ? 'مرتب‌سازی بر اساس' : 'Sort by',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'created_at',
                            child: Text('created_at'),
                          ),
                          DropdownMenuItem(
                            value: 'type',
                            child: Text('type'),
                          ),
                          DropdownMenuItem(
                            value: 'direction',
                            child: Text('direction'),
                          ),
                          DropdownMenuItem(
                            value: 'conflict_id',
                            child: Text('conflict_id'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _conflictSortDir,
                        onChanged: (v) async {
                          setState(() => _conflictSortDir = v ?? 'desc');
                          _productConflictsOffset = 0;
                          await _applyConflictFilters(offset: 0);
                        },
                        decoration: InputDecoration(
                          labelText: isFa ? 'ترتیب' : 'Sort dir',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'desc', child: Text('desc')),
                          DropdownMenuItem(value: 'asc', child: Text('asc')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _conflictSearchCtl,
                  decoration: InputDecoration(
                    labelText: isFa ? 'جستجو در تضادها' : 'Search conflicts',
                    suffixIcon: IconButton(
                      onPressed: () async {
                        _productConflictsOffset = 0;
                        await _applyConflictFilters(offset: 0);
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) async {
                    _productConflictsOffset = 0;
                    await _applyConflictFilters(offset: 0);
                  },
                ),
                if (_productConflicts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _selectedConflictIds.length == _productConflicts
                            .map((e) => e['conflict_id']?.toString() ?? '')
                            .where((id) => id.isNotEmpty)
                            .toSet()
                            .length,
                        onChanged: (v) =>
                            _toggleSelectAllConflicts(v == true),
                      ),
                      Text(
                        isFa ? 'انتخاب همه تضادها' : 'Select all conflicts',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: _productConflicts.map((item) {
                        final conflictId =
                            item['conflict_id']?.toString() ?? '';
                        final conflictType =
                            item['type']?.toString() ?? 'unknown';
                        final direction =
                            item['direction']?.toString() ?? '-';
                        final reason = item['reason']?.toString() ??
                            item['last_error']?.toString() ??
                            '-';
                        final isSelected =
                            conflictId.isNotEmpty &&
                            _selectedConflictIds.contains(conflictId);
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          onChanged: conflictId.isEmpty
                              ? null
                              : (v) => _toggleConflictSelection(
                                    conflictId,
                                    v == true,
                                  ),
                          title: Text('$conflictType • $direction'),
                          subtitle: Text(
                            'ID: ${conflictId.isEmpty ? '-' : conflictId} | $reason',
                          ),
                          secondary: IconButton(
                            tooltip: isFa ? 'جزئیات' : 'Details',
                            onPressed: () => _showConflictDetailsDialog(item),
                            icon: const Icon(Icons.info_outline),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _productConflictsOffset > 0
                              ? () async {
                                  final next = _productConflictsOffset -
                                      _productConflictsPageSize;
                                  await _applyConflictFilters(
                                    offset: next < 0 ? 0 : next,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          label: Text(isFa ? 'قبلی' : 'Previous'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _productConflictsHasMore
                              ? () async {
                                  await _applyConflictFilters(
                                    offset:
                                        _productConflictsOffset +
                                        _productConflictsPageSize,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                          label: Text(isFa ? 'بعدی' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _resolveLimitCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isFa ? 'تعداد حل تضاد' : 'Resolve limit',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: canSync && !_resolvingConflicts
                            ? () => _resolveProductConflicts('local_wins')
                            : null,
                        icon: _resolvingConflicts
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.call_split_outlined),
                        label: Text(
                          isFa ? 'حل با local_wins' : 'Resolve local_wins',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: canSync && !_resolvingConflicts
                            ? () => _resolveProductConflicts('remote_wins')
                            : null,
                        icon: const Icon(Icons.swap_horiz_outlined),
                        label: Text(
                          isFa ? 'حل با remote_wins' : 'Resolve remote_wins',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_resolvingConflicts
                      ? () => _resolveProductConflicts('discard')
                      : null,
                  icon: const Icon(Icons.remove_done_outlined),
                  label: Text(
                    isFa ? 'رد تضادها (discard)' : 'Discard conflicts',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_clearingConflicts
                      ? _clearProductConflicts
                      : null,
                  icon: _clearingConflicts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_outlined),
                  label: Text(
                    isFa ? 'پاک‌سازی صف تضادها' : 'Clear conflict queue',
                  ),
                ),
                const Divider(height: 28),
                Text(
                  isFa
                      ? 'سینک دستی سفارش (تست/بازیابی)'
                      : 'Manual order sync (test/recovery)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleOrdersCtl,
                  maxLines: 5,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: isFa
                        ? 'لیست سفارش‌ها (JSON)'
                        : 'Orders payload (JSON)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_syncing ? _manualSync : null,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(isFa ? 'اجرای سینک دستی' : 'Run manual sync'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleProductsCtl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: isFa
                        ? 'لیست کالاها (JSON)'
                        : 'Products payload (JSON)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_syncingProducts
                      ? _manualProductSync
                      : null,
                  icon: _syncingProducts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    isFa ? 'سینک دستی کالا' : 'Run manual product sync',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _samplePublishProductsCtl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: isFa
                        ? 'لیست انتشار کالا به باسلام (JSON)'
                        : 'Basalam publish payload (JSON)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_publishingProducts
                      ? _publishProducts
                      : null,
                  icon: _publishingProducts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    isFa
                        ? 'انتشار/به‌روزرسانی کالا در باسلام'
                        : 'Publish/update products to Basalam',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pullPageCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isFa ? 'صفحه Pull' : 'Pull page',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _pullPerPageCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isFa ? 'تعداد هر صفحه' : 'Per page',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_pullingProducts
                      ? _pullProducts
                      : null,
                  icon: _pullingProducts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: Text(
                    isFa
                        ? 'واکشی افزایشی کالا از باسلام'
                        : 'Pull products from Basalam',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pushSinceMinutesCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isFa ? 'از N دقیقه قبل' : 'Since minutes',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _pushLimitCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isFa ? 'حداکثر آیتم' : 'Push limit',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_pushingIncrementalProducts
                      ? _pushIncrementalProducts
                      : null,
                  icon: _pushingIncrementalProducts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_outlined),
                  label: Text(
                    isFa
                        ? 'Push افزایشی کالا به باسلام'
                        : 'Push incremental products to Basalam',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _retryLimitCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isFa ? 'تعداد retry' : 'Retry limit',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: canSync && !_retryingPublishQueue
                            ? _retryPublishQueue
                            : null,
                        icon: _retryingPublishQueue
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_outlined),
                        label: Text(
                          isFa ? 'Retry صف انتشار' : 'Retry publish queue',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_syncingPayments
                      ? _syncPayments
                      : null,
                  icon: _syncingPayments
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(
                    isFa
                        ? 'همگام‌سازی پرداخت‌های تاییدنشده'
                        : 'Sync unverified payments',
                  ),
                ),
                const Divider(height: 28),
                Text(
                  isFa
                      ? 'پل چت باسلام ↔ CRM (تست عملیاتی)'
                      : 'Basalam ↔ CRM chat bridge (operational test)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleInboundChatCtl,
                  maxLines: 5,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: isFa
                        ? 'نمونه پیام ورودی چت (JSON)'
                        : 'Inbound chat payload (JSON)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canSync && !_syncingInboundChats
                      ? _syncInboundChats
                      : null,
                  icon: _syncingInboundChats
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.forum_outlined),
                  label: Text(
                    isFa ? 'سینک پیام ورودی چت' : 'Sync inbound chat message',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _replyConversationIdCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isFa ? 'شناسه مکالمه CRM' : 'CRM conversation ID',
                  ),
                ),
                TextField(
                  controller: _replyChatIdCtl,
                  decoration: InputDecoration(
                    labelText: isFa
                        ? 'شناسه چت باسلام (اختیاری)'
                        : 'Basalam chat ID (optional)',
                  ),
                ),
                TextField(
                  controller: _replyBodyCtl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: isFa ? 'متن پاسخ اپراتور' : 'Operator reply text',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: canManage && !_sendingChatReply
                      ? _sendChatReply
                      : null,
                  icon: _sendingChatReply
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.reply_outlined),
                  label: Text(
                    isFa ? 'ارسال پاسخ به باسلام' : 'Send reply to Basalam',
                  ),
                ),
              ],
            ),
    );
  }
}
