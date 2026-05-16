import 'package:flutter/material.dart';

/// روی پلتفرم‌های غیروب استفاده نمی‌شود؛ برای تحلیل استاتیک همان API وب حفظ شده است.
class WebBarcodeScanScreen extends StatelessWidget {
  const WebBarcodeScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکن')),
      body: const Center(child: Text('اسکن وب فقط در خروجی وب در دسترس است.')),
    );
  }
}
