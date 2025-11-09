import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
      final items = await ws.listTransactions(businessId: businessId, limit: 50);
      final found = items.firstWhere(
        (e) => int.tryParse('${e['id']}') == txId,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) {
        setState(() => _tx = found);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final status = (qp['status'] ?? '').toLowerCase();
    final txId = qp['tx_id'];
    final ref = qp['ref'];

    final isSuccess = status == 'success';
    final icon = isSuccess ? Icons.check_circle : Icons.error_outline;
    final color = isSuccess ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(title: const Text('نتیجه پرداخت کیف‌پول')),
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
                  isSuccess ? 'پرداخت با موفقیت انجام شد' : 'پرداخت ناموفق بود',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (txId != null) Text('شماره تراکنش: $txId'),
            if (ref != null && ref.isNotEmpty) Text('مرجع پرداخت: $ref'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text('خطا در استعلام وضعیت: $_error', style: const TextStyle(color: Colors.red)),
            if (_tx != null) Text('وضعیت ثبت‌شده: ${_tx!['status']} - مبلغ: ${_tx!['amount']}'),
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
              label: const Text('بازگشت به کیف‌پول'),
            ),
          ],
        ),
      ),
    );
  }
}


