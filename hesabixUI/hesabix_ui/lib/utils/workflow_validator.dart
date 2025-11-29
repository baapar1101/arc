import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../l10n/app_localizations.dart';

/// Validator برای بررسی صحت workflow
class WorkflowValidator {
  /// اعتبارسنجی workflow
  static List<String> validateWorkflow({
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
    BuildContext? context,
  }) {
    final errors = <String>[];
    final t = context != null ? AppLocalizations.of(context) : null;

    // 1. باید حداقل یک trigger node وجود داشته باشد
    final triggerNodes = nodes.where((n) => n.type == WorkflowNodeType.trigger).toList();
    if (triggerNodes.isEmpty) {
      errors.add(t?.workflowValidationError ?? 'Workflow باید حداقل یک trigger داشته باشد');
    }

    // 2. بررسی node های بدون اتصال
    for (final node in nodes) {
      if (node.type != WorkflowNodeType.trigger) {
        final hasInput = connections.any((c) => c.targetNodeId == node.id);
        if (!hasInput) {
          errors.add('Node "${node.label}" بدون ورودی است');
        }
      }
    }

    // 3. بررسی circular dependencies
    if (_hasCircularDependency(nodes, connections)) {
      errors.add('Dependency دایره‌ای یافت شد. workflow نمی‌تواند شامل حلقه باشد');
    }

    // 4. بررسی node های یتیم (orphan nodes)
    final connectedNodeIds = <String>{};
    for (final conn in connections) {
      connectedNodeIds.add(conn.sourceNodeId);
      connectedNodeIds.add(conn.targetNodeId);
    }

    for (final node in nodes) {
      if (node.type != WorkflowNodeType.trigger && !connectedNodeIds.contains(node.id)) {
        errors.add('Node "${node.label}" به workflow متصل نیست');
      }
    }

    // 5. بررسی اینکه trigger ها باید خروجی داشته باشند
    for (final trigger in triggerNodes) {
      final hasOutput = connections.any((c) => c.sourceNodeId == trigger.id);
      if (!hasOutput) {
        errors.add('Trigger "${trigger.label}" باید حداقل یک خروجی داشته باشد');
      }
    }

    // 6. بررسی اینکه هر node باید label داشته باشد
    for (final node in nodes) {
      if (node.label.trim().isEmpty) {
        errors.add('Node با ID "${node.id}" باید یک نام داشته باشد');
      }
    }

    // 7. بررسی duplicate connections
    final connectionKeys = <String>{};
    for (final conn in connections) {
      final key = '${conn.sourceNodeId}_${conn.targetNodeId}';
      if (connectionKeys.contains(key)) {
        errors.add('اتصال تکراری بین node ها وجود دارد');
      }
      connectionKeys.add(key);
    }

    return errors;
  }

  /// بررسی وجود circular dependency
  static bool _hasCircularDependency(
    List<WorkflowNodeModel> nodes,
    List<WorkflowConnectionModel> connections,
  ) {
    // ساخت graph از connections
    final graph = <String, List<String>>{};
    for (final conn in connections) {
      graph.putIfAbsent(conn.sourceNodeId, () => []).add(conn.targetNodeId);
    }

    // DFS برای تشخیص cycle
    final visited = <String>{};
    final recStack = <String>{};

    for (final node in nodes) {
      if (!visited.contains(node.id)) {
        if (_hasCycleDFS(node.id, graph, visited, recStack)) {
          return true;
        }
      }
    }

    return false;
  }

  /// DFS helper برای تشخیص cycle
  static bool _hasCycleDFS(
    String nodeId,
    Map<String, List<String>> graph,
    Set<String> visited,
    Set<String> recStack,
  ) {
    visited.add(nodeId);
    recStack.add(nodeId);

    final neighbors = graph[nodeId] ?? [];
    for (final neighbor in neighbors) {
      if (!visited.contains(neighbor)) {
        if (_hasCycleDFS(neighbor, graph, visited, recStack)) {
          return true;
        }
      } else if (recStack.contains(neighbor)) {
        return true; // Cycle detected
      }
    }

    recStack.remove(nodeId);
    return false;
  }

  /// بررسی اینکه workflow قابل اجرا است یا نه
  static bool isWorkflowExecutable({
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
  }) {
    final errors = validateWorkflow(nodes: nodes, connections: connections);
    return errors.isEmpty;
  }
}

