import '../models/workflow_editor_models.dart';

/// آیا کلید متادیتای تریگر/اکشن (ثبت‌شده در رجیستری بک‌اند) مربوط به باسلام است؟
bool workflowMetadataKeyReferencesBasalam(String key) {
  final k = key.trim().toLowerCase();
  if (k.isEmpty) return false;
  return k.startsWith('basalam.') || k.startsWith('basalam_');
}

/// آیا این نود برای اجرا به افزونهٔ باسلام وابسته است؟
bool workflowNodeReferencesBasalam(WorkflowNodeModel node) {
  final k = node.key;
  if (k != null && workflowMetadataKeyReferencesBasalam(k)) return true;
  final c = node.config;
  final tt = c['trigger_type'];
  if (tt is String && workflowMetadataKeyReferencesBasalam(tt)) return true;
  final at = c['action_type'];
  if (at is String && workflowMetadataKeyReferencesBasalam(at)) return true;
  return false;
}
