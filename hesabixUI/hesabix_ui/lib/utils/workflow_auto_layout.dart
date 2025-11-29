import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/workflow_editor_models.dart';
import 'workflow_constants.dart';

enum WorkflowAutoLayoutType {
  hierarchical,
  forceDirected,
}

/// Auto-layout algorithm برای چیدمان خودکار node ها
class WorkflowAutoLayout {
  static Map<String, Offset> applyLayout({
    required WorkflowAutoLayoutType type,
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
  }) {
    switch (type) {
      case WorkflowAutoLayoutType.hierarchical:
        return applyHierarchicalLayout(nodes: nodes, connections: connections);
      case WorkflowAutoLayoutType.forceDirected:
        return applyForceDirectedLayout(nodes: nodes, connections: connections);
    }
  }

  /// اعمال auto-layout hierarchical
  static Map<String, Offset> applyHierarchicalLayout({
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
    double? horizontalSpacing,
    double? verticalSpacing,
  }) {
    final hSpacing = horizontalSpacing ?? WorkflowConstants.horizontalSpacing;
    final vSpacing = verticalSpacing ?? WorkflowConstants.verticalSpacing;
    if (nodes.isEmpty) return {};

    final positions = <String, Offset>{};

    // پیدا کردن trigger node ها (node های بدون ورودی)
    final triggerNodes = nodes.where((n) => n.type == WorkflowNodeType.trigger).toList();

    if (triggerNodes.isEmpty) {
      // اگر trigger نبود، node های بدون ورودی
      final nodesWithInput = connections.map((c) => c.targetNodeId).toSet();
      triggerNodes.addAll(nodes.where((n) => !nodesWithInput.contains(n.id)));
    }

    // ساخت graph
    final graph = <String, List<String>>{};
    for (final conn in connections) {
      graph.putIfAbsent(conn.sourceNodeId, () => []).add(conn.targetNodeId);
    }

    // BFS برای لایه‌بندی
    final layers = <List<String>>[];
    final visited = <String>{};
    final queue = triggerNodes.map((n) => n.id).toList();

    // لایه 0: trigger ها
    if (triggerNodes.isNotEmpty) {
      layers.add(triggerNodes.map((n) => n.id).toList());
      visited.addAll(triggerNodes.map((n) => n.id));
    }

    // لایه‌های بعدی
    while (queue.isNotEmpty) {
      final currentLayer = <String>[];
      final queueSize = queue.length;

      for (int i = 0; i < queueSize; i++) {
        final nodeId = queue.removeAt(0);
        final neighbors = graph[nodeId] ?? [];

        for (final neighbor in neighbors) {
          if (!visited.contains(neighbor)) {
            // بررسی که همه پیش‌نیازها آماده باشند
            final prerequisites = connections
                .where((c) => c.targetNodeId == neighbor)
                .map((c) => c.sourceNodeId)
                .toList();

            if (prerequisites.every((p) => visited.contains(p))) {
              currentLayer.add(neighbor);
              visited.add(neighbor);
              queue.add(neighbor);
            }
          }
        }
      }

      if (currentLayer.isNotEmpty) {
        layers.add(currentLayer);
      }
    }

    // قرار دادن node های بدون اتصال
    for (final node in nodes) {
      if (!visited.contains(node.id)) {
        if (layers.isEmpty) {
          layers.add([node.id]);
        } else {
          layers.last.add(node.id);
        }
      }
    }

    // محاسبه موقعیت‌ها
    double startX = 100;
    for (int layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final layerHeight = layer.length * vSpacing;
      final startY = (1000 - layerHeight) / 2; // وسط صفحه

      for (int nodeIndex = 0; nodeIndex < layer.length; nodeIndex++) {
        final nodeId = layer[nodeIndex];
        final x = startX + (layerIndex * hSpacing);
        final y = startY + (nodeIndex * vSpacing);
        positions[nodeId] = Offset(x, y);
      }
    }

    return positions;
  }

  /// اعمال auto-layout ساده (چیدمان خطی)
  static Map<String, Offset> applySimpleLayout({
    required List<WorkflowNodeModel> nodes,
    double spacing = 200,
    Offset startPosition = const Offset(100, 100),
  }) {
    final positions = <String, Offset>{};
    double currentY = startPosition.dy;

    // مرتب‌سازی node ها بر اساس نوع (trigger اول)
    final sortedNodes = List<WorkflowNodeModel>.from(nodes);
    sortedNodes.sort((a, b) {
      if (a.type == WorkflowNodeType.trigger && b.type != WorkflowNodeType.trigger) {
        return -1;
      }
      if (a.type != WorkflowNodeType.trigger && b.type == WorkflowNodeType.trigger) {
        return 1;
      }
      return 0;
    });

    for (final node in sortedNodes) {
      positions[node.id] = Offset(startPosition.dx, currentY);
      currentY += spacing;
    }

    return positions;
  }

  /// اعمال force-directed layout (الگوریتم Fruchterman-Reingold ساده‌شده)
  static Map<String, Offset> applyForceDirectedLayout({
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
    Size? canvasSize,
    int? iterations,
    double? repulsiveForce,
    double? springLength,
    double? springConstant,
    double? damping,
  }) {
    final canvas = canvasSize ?? WorkflowConstants.defaultCanvasSize;
    final iter = iterations ?? WorkflowConstants.defaultIterations;
    final repForce = repulsiveForce ?? WorkflowConstants.repulsiveForce;
    final sprLength = springLength ?? WorkflowConstants.springLength;
    final sprConstant = springConstant ?? WorkflowConstants.springConstant;
    final damp = damping ?? WorkflowConstants.damping;
    if (nodes.isEmpty) return {};

    final positions = <String, Offset>{};
    final velocities = <String, Offset>{};
    final random = math.Random();

    // مقداردهی اولیه بر اساس موقعیت فعلی یا تصادفی
    for (final node in nodes) {
      positions[node.id] = node.position == Offset.zero
          ? Offset(
              random.nextDouble() * canvas.width,
              random.nextDouble() * canvas.height,
            )
          : node.position;
      velocities[node.id] = Offset.zero;
    }

    // adjacency list
    final adjacency = <String, List<String>>{};
    for (final conn in connections) {
      adjacency.putIfAbsent(conn.sourceNodeId, () => []).add(conn.targetNodeId);
      adjacency.putIfAbsent(conn.targetNodeId, () => []).add(conn.sourceNodeId);
    }

    for (int iteration = 0; iteration < iter; iteration++) {
      final forces = <String, Offset>{};

      // نیروی دافعه بین همه node ها
      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final nodeA = nodes[i];
          final nodeB = nodes[j];
          final posA = positions[nodeA.id]!;
          final posB = positions[nodeB.id]!;
          final delta = posA - posB;
          final distance = delta.distance.clamp(0.01, 1000.0);
          final forceMagnitude = repForce / (distance * distance);
          final force = Offset(
            delta.dx / distance * forceMagnitude,
            delta.dy / distance * forceMagnitude,
          );
          forces[nodeA.id] = (forces[nodeA.id] ?? Offset.zero) + force;
          forces[nodeB.id] = (forces[nodeB.id] ?? Offset.zero) - force;
        }
      }

      // نیروی جاذبه برای connections (فنر)
      for (final node in nodes) {
        final neighbors = adjacency[node.id] ?? [];
        final posA = positions[node.id]!;
        for (final neighborId in neighbors) {
          final posB = positions[neighborId]!;
          final delta = posB - posA;
          final distance = delta.distance.clamp(0.01, 1000.0);
          final displacement = distance - sprLength;
          final forceMagnitude = sprConstant * displacement;
          final force = Offset(
            delta.dx / distance * forceMagnitude,
            delta.dy / distance * forceMagnitude,
          );
          forces[node.id] = (forces[node.id] ?? Offset.zero) + force;
          forces[neighborId] = (forces[neighborId] ?? Offset.zero) - force;
        }
      }

      // به‌روزرسانی موقعیت‌ها
      for (final node in nodes) {
        final nodeId = node.id;
        final velocity = velocities[nodeId] ?? Offset.zero;
        final acceleration = forces[nodeId] ?? Offset.zero;
        final newVelocity = (velocity + acceleration) * damp;
        var newPosition = positions[nodeId]! + newVelocity;

        // جلوگیری از خروج از canvas
        newPosition = Offset(
          newPosition.dx.clamp(50, canvas.width - 230),
          newPosition.dy.clamp(50, canvas.height - 130),
        );

        velocities[nodeId] = newVelocity;
        positions[nodeId] = newPosition;
      }
    }

    return positions;
  }
}

