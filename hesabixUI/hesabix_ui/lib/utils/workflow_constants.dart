import 'package:flutter/material.dart';

/// Constants برای workflow editor
class WorkflowConstants {
  // اندازه node
  static const double nodeWidth = 180.0;
  static const double nodeHeight = 100.0;
  
  // موقعیت connection points نسبت به node
  static const double connectionPointSize = 16.0;
  static const double connectionPointHighlightSize = 24.0;
  
  // فاصله‌ها
  static const double defaultSpacing = 200.0;
  static const double gridSize = 20.0;
  
  // Canvas
  static const Size defaultCanvasSize = Size(2000, 2000);
  
  // Zoom limits
  static const double minZoom = 0.5;
  static const double maxZoom = 3.0;
  
  // Auto-layout
  static const double horizontalSpacing = 250.0;
  static const double verticalSpacing = 150.0;
  
  // Force-directed layout
  static const int defaultIterations = 200;
  static const double repulsiveForce = 6000.0;
  static const double springLength = 220.0;
  static const double springConstant = 0.1;
  static const double damping = 0.85;
  
  // Helper methods
  static Offset getNodeCenter(Offset position) {
    return Offset(
      position.dx + nodeWidth / 2,
      position.dy + nodeHeight / 2,
    );
  }
  
  static Offset getConnectionPoint(Offset nodePosition, String side) {
    switch (side) {
      case 'top':
        return Offset(nodePosition.dx + nodeWidth / 2, nodePosition.dy);
      case 'bottom':
        return Offset(nodePosition.dx + nodeWidth / 2, nodePosition.dy + nodeHeight);
      case 'left':
        return Offset(nodePosition.dx, nodePosition.dy + nodeHeight / 2);
      case 'right':
        return Offset(nodePosition.dx + nodeWidth, nodePosition.dy + nodeHeight / 2);
      default:
        return Offset(nodePosition.dx + nodeWidth / 2, nodePosition.dy + nodeHeight);
    }
  }
  
  static Rect getNodeRect(Offset position) {
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      nodeWidth,
      nodeHeight,
    );
  }
}

