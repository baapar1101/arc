import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// صفحهٔ تمام‌صفحه برای اسکن بارکد و QR با دوربین (native: اندروید، iOS، macOS).
/// روی وب از [WebBarcodeScanScreen] استفاده می‌شود.
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

  Future<void> _closeScanner() async {
    await _controller.stop();
    if (mounted) Navigator.of(context).pop<String>();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (e, st) {
      debugPrint('MobileBarcodeScan: toggleTorch failed: $e\n$st');
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (e, st) {
      debugPrint('MobileBarcodeScan: switchCamera failed: $e\n$st');
    }
  }

  bool _canSwitchCamera(MobileScannerState s) {
    final n = s.availableCameras;
    if (n == null) return true;
    return n > 1;
  }

  bool _torchAvailable(MobileScannerState s) {
    return s.torchState != TorchState.unavailable;
  }

  IconData _torchIcon(MobileScannerState s) {
    switch (s.torchState) {
      case TorchState.on:
        return Icons.flash_on;
      case TorchState.auto:
        return Icons.flash_auto;
      case TorchState.off:
      case TorchState.unavailable:
        return Icons.flash_off;
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
          onPressed: _closeScanner,
        ),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final s = _controller.value;
              final torchOn = s.torchState == TorchState.on || s.torchState == TorchState.auto;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _torchAvailable(s)
                        ? (torchOn ? 'خاموش کردن فلش' : 'روشن کردن فلش')
                        : 'فلش در دسترس نیست',
                    onPressed: _torchAvailable(s) ? _toggleTorch : null,
                    icon: Icon(_torchIcon(s)),
                  ),
                  IconButton(
                    tooltip: 'تعویض دوربین (جلو / عقب)',
                    onPressed: _canSwitchCamera(s) ? _switchCamera : null,
                    icon: const Icon(Icons.cameraswitch),
                  ),
                ],
              );
            },
          ),
        ],
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
