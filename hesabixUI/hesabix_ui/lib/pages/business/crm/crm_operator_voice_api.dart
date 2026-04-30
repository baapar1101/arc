import 'dart:typed_data';

/// کنترل ضبط سریع ویس برای پیام اپراتور در چت وب CRM (فقط платفرم‌های غیروب).
abstract class OperatorVoiceController {
  Future<bool> ensureReady();

  Future<bool> startRecording();

  /// بازگشت [null] یعنی لغو یا خطا بدون آپلود.
  Future<(Uint8List bytes, String filename)?> stopAndRead();

  Future<void> dispose();
}
