import 'package:hesabix_ui/models/ai_stream_event.dart';

const kSubagentLifecycleTools = {
  'spawn_subagent',
  'await_subagent',
  'cancel_subagent',
};

bool isSubagentLifecycleTool(String? tool) =>
    tool != null && kSubagentLifecycleTools.contains(tool);

List<AIAgentTraceStep> subagentChildSteps(
  List<AIAgentTraceStep> all,
  AIAgentTraceStep parent,
) {
  final pid = parent.stepId;
  final sid = parent.cancelableSubagentId ?? parent.subagentId;
  return all.where((s) {
    if (s.stepId == parent.stepId) return false;
    if (s.kind == 'subagent') return false;
    if (s.parentStepId != null && s.parentStepId == pid) return true;
    if (sid != null &&
        sid.isNotEmpty &&
        s.subagentId == sid &&
        s.parentStepId != null) {
      return true;
    }
    return false;
  }).toList();
}

/// گام‌های ریشهٔ تایم‌لاین — بدون ابزار spawn و بدون فرزندان تو در تو.
List<AIAgentTraceStep> timelineRootSteps(List<AIAgentTraceStep> all) {
  return all.where((s) {
    if (s.isNestedSubagentStep) return false;
    if (s.kind != 'subagent' && isSubagentLifecycleTool(s.tool)) return false;
    return true;
  }).toList();
}
