import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

// ——— BarcodeDetector (Shape Detection API) ———
// در مرورگرهایی مثل کروم/اج موجود است؛ در سافاری ممکن است نباشد.

@anonymous
extension type _BarcodeDetectorOptions._(JSObject _) implements JSObject {
  external factory _BarcodeDetectorOptions({required JSArray<JSString> formats});
}

@JS('BarcodeDetector')
extension type _JsBarcodeDetector._(JSObject _) implements JSObject {
  external factory _JsBarcodeDetector(_BarcodeDetectorOptions options);

  external JSPromise<JSArray<_DetectedBarcode>> detect(JSObject imageBitmapSource);
}

extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external JSString? get rawValue;
}

/// اسکن بارکد و QR در وب: [getUserMedia] + [BarcodeDetector]؛ در نبود API، ورود دستی کد.
class WebBarcodeScanScreen extends StatefulWidget {
  const WebBarcodeScanScreen({super.key});

  @override
  State<WebBarcodeScanScreen> createState() => _WebBarcodeScanScreenState();
}

class _WebBarcodeScanScreenState extends State<WebBarcodeScanScreen> {
  static JSArray<JSString> get _formats => <JSString>[
        'aztec'.toJS,
        'code_128'.toJS,
        'code_39'.toJS,
        'code_93'.toJS,
        'codabar'.toJS,
        'data_matrix'.toJS,
        'ean_13'.toJS,
        'ean_8'.toJS,
        'itf'.toJS,
        'pdf417'.toJS,
        'qr_code'.toJS,
        'upc_a'.toJS,
        'upc_e'.toJS,
      ].toJS;

  String? _viewType;
  web.HTMLVideoElement? _surfaceVideo;
  web.MediaStream? _mediaStream;
  _JsBarcodeDetector? _detector;
  Timer? _scanTimer;

  bool _handled = false;
  bool _detectBusy = false;
  bool _cameraStarting = false;
  String? _errorText;
  int _waitVideoAttempts = 0;

  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _registerViewFactory();
  }

  void _registerViewFactory() {
    final vt =
        'hesabix-web-barcode-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _viewType = vt;
    ui_web.platformViewRegistry.registerViewFactory(vt, (int viewId) {
      final video = web.HTMLVideoElement();
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = 'cover';
      video.playsInline = true;
      video.muted = true;
      video.autoplay = true;

      _surfaceVideo = video;

      final wrap = web.document.createElement('div') as web.HTMLDivElement;
      wrap.style.width = '100%';
      wrap.style.height = '100%';
      wrap.style.backgroundColor = '#000000';
      wrap.appendChild(video);
      return wrap;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _waitForVideoAndStart());
  }

  void _waitForVideoAndStart() {
    if (!mounted || _handled) return;
    if (_surfaceVideo != null) {
      unawaited(_openCameraAndScanner());
      return;
    }
    _waitVideoAttempts++;
    if (_waitVideoAttempts > 80) {
      setState(() {
        _errorText = 'پیش‌نمایش دوربین آماده نشد. کد را دستی وارد کنید.';
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 25), _waitForVideoAndStart);
    });
  }

  Future<void> _openCameraAndScanner() async {
    if (_handled || !mounted) return;
    final video = _surfaceVideo;
    if (video == null) return;

    setState(() {
      _cameraStarting = true;
      _errorText = null;
    });

    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(
            video: true.toJS,
            audio: false.toJS,
          ))
          .toDart;

      if (!mounted || _handled) {
        _stopStream(stream);
        return;
      }

      _mediaStream = stream;
      video.srcObject = stream;
      await video.play().toDart;

      _JsBarcodeDetector? det;
      try {
        det = _JsBarcodeDetector(_BarcodeDetectorOptions(formats: _formats));
      } catch (e, st) {
        debugPrint('WebBarcodeScan: BarcodeDetector init failed: $e\n$st');
        det = null;
      }

      if (!mounted || _handled) {
        _cleanupStream();
        return;
      }

      setState(() {
        _detector = det;
        _cameraStarting = false;
        if (det == null) {
          _errorText =
              'اسکن خودکار در این مرورگر در دسترس نیست (BarcodeDetector). می‌توانید کد را دستی وارد کنید یا اسکنر USB متصل به کیبورد استفاده کنید.';
        }
      });

      if (det != null) {
        _scanTimer?.cancel();
        _scanTimer = Timer.periodic(const Duration(milliseconds: 220), (_) => _tickDetect());
      }
    } catch (e, st) {
      debugPrint('WebBarcodeScan: camera error: $e\n$st');
      if (mounted) {
        setState(() {
          _cameraStarting = false;
          _errorText =
              'دسترسی به دوربین ممکن نشد. HTTPS یا localhost لازم است؛ یا اجازهٔ دوربین را بدهید. جزئیات: $e';
        });
      }
    }
  }

  void _tickDetect() {
    if (_handled || !mounted) return;
    final det = _detector;
    final video = _surfaceVideo;
    if (det == null || video == null || _detectBusy) return;
    if (video.readyState < 2) return;

    _detectBusy = true;
    unawaited(_runDetectOnce(det, video));
  }

  Future<void> _runDetectOnce(_JsBarcodeDetector det, web.HTMLVideoElement video) async {
    try {
      final arr = await det.detect(video as JSObject).toDart;
      for (final d in arr.toDart) {
        final raw = d.rawValue?.toDart.trim();
        if (raw != null && raw.isNotEmpty) {
          if (mounted && !_handled) {
            _handled = true;
            _scanTimer?.cancel();
            _cleanupStream();
            Navigator.of(context).pop<String>(raw);
          }
          return;
        }
      }
    } catch (e, st) {
      debugPrint('WebBarcodeScan: detect frame error: $e\n$st');
    } finally {
      _detectBusy = false;
    }
  }

  void _stopStream(web.MediaStream stream) {
    try {
      final tracks = stream.getTracks();
      for (final t in tracks.toDart) {
        try {
          t.stop();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _cleanupStream() {
    final s = _mediaStream;
    _mediaStream = null;
    if (s != null) {
      _stopStream(s);
    }
    final v = _surfaceVideo;
    if (v != null) {
      try {
        v.srcObject = null;
      } catch (_) {}
    }
  }

  void _submitManual() {
    final t = _manualController.text.trim();
    if (t.isEmpty) return;
    if (!_handled) {
      _handled = true;
      _scanTimer?.cancel();
      _cleanupStream();
      Navigator.of(context).pop<String>(t);
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cleanupStream();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vt = _viewType;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اسکن بارکد یا QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (!_handled) {
              _handled = true;
              _scanTimer?.cancel();
              _cleanupStream();
              Navigator.of(context).pop<String>();
            }
          },
        ),
      ),
      body: Column(
        children: [
          if (_cameraStarting)
            const LinearProgressIndicator(minHeight: 2, color: Colors.white),
          Expanded(
            child: vt == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      HtmlElementView(viewType: vt),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 20,
                        child: Text(
                          'بارکد یا QR را جلوی دوربین قرار دهید',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            shadows: const [
                              Shadow(blurRadius: 8, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_errorText != null)
            Material(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
                ),
              ),
            ),
          Material(
            color: Colors.grey.shade900,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'ورود دستی کد',
                          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                          hintText: 'بارکد، QR یا کد کالا',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        onSubmitted: (_) => _submitManual(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitManual,
                      child: const Text('تایید'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
