import 'package:flutter/material.dart';

/// صفحه نمایش نتیجه پرداخت
/// این صفحه وقتی از طریق Deep Link باز می‌شود نمایش داده می‌شود
class PaymentResultPage extends StatefulWidget {
  final int? txId;
  final String? status;
  final double? amount;
  final String? ref;

  const PaymentResultPage({
    super.key,
    this.txId,
    this.status,
    this.amount,
    this.ref,
  });

  @override
  State<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends State<PaymentResultPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get isSuccess => widget.status == 'success';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSuccess
                ? [Colors.green.shade400, Colors.green.shade700]
                : [Colors.red.shade400, Colors.red.shade700],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // آیکون انیمیشن‌دار
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        isSuccess ? Icons.check : Icons.close,
                        size: 80,
                        color: isSuccess ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // عنوان
                  Text(
                    isSuccess ? 'پرداخت موفق!' : 'پرداخت ناموفق',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // پیام
                  Text(
                    isSuccess
                        ? 'تراکنش شما با موفقیت انجام شد و کیف پول شما شارژ گردید.'
                        : 'متأسفانه تراکنش شما با موفقیت انجام نشد.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // کارت اطلاعات
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (widget.amount != null)
                          _buildDetailRow(
                            'مبلغ',
                            '${widget.amount!.toStringAsFixed(0)} ریال',
                          ),
                        if (widget.txId != null)
                          _buildDetailRow(
                            'شماره تراکنش',
                            widget.txId.toString(),
                          ),
                        if (widget.ref != null)
                          _buildDetailRow(
                            'شماره پیگیری',
                            widget.ref!,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // دکمه‌ها
                  Row(
                    children: [
                      if (!isSuccess)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              // هدایت به صفحه افزایش اعتبار
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'تلاش مجدد',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (!isSuccess) const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // هدایت به داشبورد
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.white,
                            foregroundColor:
                                isSuccess ? Colors.green : Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'بازگشت به داشبورد',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

