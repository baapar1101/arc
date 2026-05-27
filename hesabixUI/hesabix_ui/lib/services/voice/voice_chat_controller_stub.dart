/// نسخه‌ی stub برای پلتفرم‌های غیرپشتیبانی‌شده.
/// هدف: build وب نشکند و UI بتواند پیام مناسب نشان دهد.
class VoiceChatController {
  VoiceChatController({
    required this.sessionId,
    required this.collectDataOptIn,
    required this.onEvent,
    required this.onError,
  });

  final int sessionId;
  final bool collectDataOptIn;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(String message) onError;

  bool get isActive => false;
  bool get isRecording => false;

  Future<void> start() async {
    onError('مکالمه صوتی روی این پلتفرم پشتیبانی نمی‌شود.');
  }

  Future<void> startRecording() async {}
  Future<void> stopRecording() async {}
  Future<void> stop() async {}
  Future<void> dispose() async {}
}


