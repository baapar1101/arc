import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// نتیجه شروع ضبط در مرورگر.
enum VoiceWebCaptureMode {
  pcmWorklet,
  webmOpus,
}

extension type _HesabixVoiceCapture._(JSObject _) implements JSObject {
  external bool supportsWebmOpus();
  external JSPromise<JSAny?> start(
    web.AudioContext ctx,
    int targetSampleRate,
    JSFunction onPcmFrame,
    JSFunction? onWebmChunk,
  );
  external JSPromise stop();
  external JSString getMode();
}

@JS('HesabixVoiceCapture')
external _HesabixVoiceCapture get _hesabixVoiceCapture;

/// ضبط صوت وب از طریق `hesabix_voice_capture.js` (محلی، بدون API ابری).
class VoiceWebCapture {
  VoiceWebCapture({
    required this.onPcmFrame,
    this.onWebmChunk,
  });

  final void Function(Uint8List pcm) onPcmFrame;
  final void Function(Uint8List webm)? onWebmChunk;

  VoiceWebCaptureMode _mode = VoiceWebCaptureMode.pcmWorklet;

  VoiceWebCaptureMode get mode => _mode;

  static bool get supportsWebmOpus => _hesabixVoiceCapture.supportsWebmOpus();

  Future<VoiceWebCaptureMode> start(web.AudioContext ctx, int targetSampleRate) async {
    await _hesabixVoiceCapture
        .start(
          ctx,
          targetSampleRate,
          ((JSAny? buffer) {
            if (buffer.isA<JSArrayBuffer>()) {
              final bytes = (buffer! as JSArrayBuffer).toDart;
              onPcmFrame(bytes.asUint8List());
            }
          }).toJS,
          onWebmChunk == null
              ? null
              : ((JSAny? buffer) {
                  if (buffer.isA<JSArrayBuffer>()) {
                    final bytes = (buffer! as JSArrayBuffer).toDart;
                    onWebmChunk!(bytes.asUint8List());
                  }
                }).toJS,
        )
        .toDart;

    final modeStr = _hesabixVoiceCapture.getMode().toDart;
    _mode = modeStr == 'webm'
        ? VoiceWebCaptureMode.webmOpus
        : VoiceWebCaptureMode.pcmWorklet;
    return _mode;
  }

  Future<void> stop() async {
    await _hesabixVoiceCapture.stop().toDart;
  }
}
