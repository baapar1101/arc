/// وضعیت‌های نمایشی مکالمه صوتی AI در UI.
enum VoicePhase {
  idle,
  connecting,
  listening,
  processing,
  speaking,
  error,
}

extension VoicePhaseX on VoicePhase {
  bool get isActive =>
      this != VoicePhase.idle && this != VoicePhase.error;

  /// کلید l10n برای نوار وضعیت (مقدار `aiVoiceStatus*`).
  String? get l10nKey {
    switch (this) {
      case VoicePhase.idle:
      case VoicePhase.error:
        return null;
      case VoicePhase.connecting:
        return 'aiVoiceStatusConnecting';
      case VoicePhase.listening:
        return 'aiVoiceStatusListening';
      case VoicePhase.processing:
        return 'aiVoiceStatusProcessing';
      case VoicePhase.speaking:
        return 'aiVoiceStatusSpeaking';
    }
  }
}
