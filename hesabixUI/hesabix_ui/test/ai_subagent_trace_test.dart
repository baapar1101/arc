import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_subagent_trace.dart';

void main() {
  test('timeline hides spawn tools and nested child steps', () {
    const parent = AIAgentTraceStep(
      stepId: 'subagent_abc',
      kind: 'subagent',
      state: 'active',
      subagentId: 'abc',
      exploreTarget: 'abc',
    );
    const spawnTool = AIAgentTraceStep(
      stepId: 'tool_1',
      kind: 'tool',
      tool: 'spawn_subagent',
      state: 'done',
    );
    const child = AIAgentTraceStep(
      stepId: 'sa_abc_tool_0',
      kind: 'tool',
      tool: 'get_sales_report',
      state: 'active',
      subagentId: 'abc',
      parentStepId: 'subagent_abc',
    );
    const other = AIAgentTraceStep(
      stepId: 'plan_1',
      kind: 'plan',
      state: 'done',
    );
    final roots = timelineRootSteps([spawnTool, parent, child, other]);
    expect(roots.map((s) => s.stepId), ['subagent_abc', 'plan_1']);
    final nested = subagentChildSteps([spawnTool, parent, child, other], parent);
    expect(nested.map((s) => s.stepId), ['sa_abc_tool_0']);
  });
}
