import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// صفحهٔ تمام‌صفحه برای اسکن بارکد و QR با دوربین (موبایل؛ پلاگین `mobile_scanner` وب را پشتیبانی نمی‌کند).
/// در صورت موفقیت، مقدار خوانده‌شده را با [Navigator.pop] برمی‌گرداند.
class MobileBarcodeScanScreen extends StatefulWidget {
  const MobileBarcodeScanScreen({super.key});

  @override
  State<MobileBarcodeScanScreen> createState() => _MobileBarcodeScanScreenState();
}

class _MobileBarcodeScanScreenState extends State<MobileBarcodeScanScreen> {
  bool _handled = false;
  late final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    unawaited(_handleCaptureAsync(capture));
  }

  Future<void> _handleCaptureAsync(BarcodeCapture capture) async {
    if (_handled || !mounted) return;
    for (final b in capture.barcodes) {
      final text = b.rawValue ?? b.displayValue;
      if (text != null && text.trim().isNotEmpty) {
        _handled = true;
        await _controller.stop();
        if (mounted) Navigator.of(context).pop<String>(text.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اسکن بارکد یا QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop<String>(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            tapToFocus: true,
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'بارکد یا کیوآرکد را در مقابل دوربین قرار دهید',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
