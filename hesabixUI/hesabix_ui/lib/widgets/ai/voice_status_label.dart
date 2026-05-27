import '../../l10n/app_localizations.dart';
import '../../services/voice/voice_phase.dart';
import 'ai_chat_l10n.dart';

/// برچسب وضعیت مکالمه صوتی برای نوار composer.
String? voiceStatusLabel(
  AppLocalizations l10n,
  VoicePhase phase, {
  Map<String, dynamic>? lastVoiceStatusEvent,
}) {
  if (lastVoiceStatusEvent != null) {
    final type = lastVoiceStatusEvent['type'] as String?;
    if (type == 'voice_status') {
      final serverPhase = lastVoiceStatusEvent['phase'] as String?;
      if (serverPhase == 'tool_running') {
        final label = lastVoiceStatusEvent['label'] as String?;
        final toolKey = lastVoiceStatusEvent['tool_key'] as String?;
        final toolName = label?.trim().isNotEmpty == true
            ? label!
            : (toolKey != null ? aiToolLabel(l10n, '', toolKey: toolKey) : l10n.aiToolGeneric);
        return l10n.aiStatusRunningTool(toolName);
      }
      if (serverPhase == 'planning_tools') {
        return l10n.aiStatusPlanningTools;
      }
      if (serverPhase == 'writing') {
        return l10n.aiStatusWriting;
      }
      if (serverPhase == 'thinking') {
        return l10n.aiStatusThinking;
      }
      if (serverPhase == 'speaking') {
        return l10n.aiVoiceStatusSpeaking;
      }
      if (serverPhase == 'listening') {
        return l10n.aiVoiceStatusListening;
      }
    }
  }

  switch (phase) {
    case VoicePhase.idle:
    case VoicePhase.error:
      return null;
    case VoicePhase.connecting:
      return l10n.aiVoiceStatusConnecting;
    case VoicePhase.listening:
      return l10n.aiVoiceStatusListening;
    case VoicePhase.processing:
      return l10n.aiVoiceStatusProcessing;
    case VoicePhase.speaking:
      return l10n.aiVoiceStatusSpeaking;
  }
}
