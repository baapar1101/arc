import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../services/wallet_service.dart';
import '../../core/api_client.dart';

class WalletPaymentResultPage extends StatefulWidget {
  final AuthStore authStore;
  const WalletPaymentResultPage({super.key, required this.authStore});

  @override
  State<WalletPaymentResultPage> createState() => _WalletPaymentResultPageState();
}

class _WalletPaymentResultPageState extends State<WalletPaymentResultPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _tx;

  @override
  void initState() {
    super.initState();
    _checkStatusIfPossible();
  }

  Future<void> _checkStatusIfPossible() async {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final txId = int.tryParse(qp['tx_id'] ?? '');
    final businessId = widget.authStore.currentBusiness?.id;
    if (txId == null || businessId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient();
      final ws = WalletService(api);
      // تلاش برای پیدا کردن تراکنش با محدودیت بیشتر
      List<Map<String, dynamic>> items = [];
      int skip = 0;
      const int limit = 100;
      bool found = false;
      
      // جستجو در چندین صفحه
      for (int i = 0; i < 5 && !found; i++) {
        final batch = await ws.listTransactions(
          businessId: businessId,
          limit: limit,
          skip: skip,
        );
        if (batch.isEmpty) break;
        
        items.addAll(batch);
        final tx = batch.firstWhere(
          (e) => int.tryParse('${e['id']}') == txId,
          orElse: () => <String, dynamic>{},
        );
        
        if (tx.isNotEmpty) {
          setState(() => _tx = tx);
          found = true;
          break;
        }
        
        // اگر تراکنش پیدا نشد و تعداد کمتر از limit است، دیگر ادامه نده
        if (batch.length < limit) break;
        skip += limit;
      }
      
      // اگر پیدا نشد، از API مستقیم درخواست کنیم (اگر endpoint وجود دارد)
      if (!found && txId > 0) {
        // تلاش برای دریافت مستقیم تراکنش از طریق API
        try {
          final allItems = await ws.listTransactions(
            businessId: businessId,
            limit: 1000, // افزایش محدودیت
            skip: 0,
          );
          final tx = allItems.firstWhere(
            (e) => int.tryParse('${e['id']}') == txId,
            orElse: () => <String, dynamic>{},
          );
          if (tx.isNotEmpty) {
            setState(() => _tx = tx);
            found = true;
          }
        } catch (_) {
          // اگر خطا رخ داد، ادامه می‌دهیم
        }
      }
      
      if (!found) {
        setState(() => _error = 'تراکنش یافت نشد. ممکن است تراکنش در لیست اخیر نباشد.');
      }
    } catch (e) {
      setState(() => _error = 'خطا در بررسی وضعیت: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final qp = GoRouterState.of(context).uri.queryParameters;
    final status = (qp['status'] ?? '').toLowerCase();
    final txId = qp['tx_id'];
    final ref = qp['ref'];

    final isSuccess = status == 'success';
    final icon = isSuccess ? Icons.check_circle : Icons.error_outline;
    final color = isSuccess ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(title: Text(t.walletPaymentResultTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Text(
                  isSuccess ? t.walletPaymentSuccess : t.walletPaymentFailed,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (txId != null) Text('${t.transactionId}: $txId'),
            if (ref != null && ref.isNotEmpty) Text('${t.paymentReference}: $ref'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text('${t.walletStatusCheckErrorPrefix} $_error', style: const TextStyle(color: Colors.red)),
            if (_tx != null) Text('${t.status}: ${_tx!['status']} - ${t.moneyAmount}: ${_tx!['amount']}'),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                final bid = widget.authStore.currentBusiness?.id;
                if (bid != null) {
                  context.go('/business/$bid/wallet');
                } else {
                  context.go('/user/profile/dashboard');
                }
              },
              icon: const Icon(Icons.account_balance_wallet),
              label: Text(t.walletBackToWallet),
            ),
          ],
        ),
      ),
    );
  }
}


