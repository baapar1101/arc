import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../utils/workflow_constants.dart';

/// Painter برای رسم خطوط اتصال بین node ها
class WorkflowConnectionPainter extends CustomPainter {
  final List<WorkflowConnectionModel> connections;
  final Map<String, Offset> nodePositions; // nodeId -> position
  final String? selectedConnectionId;
  final bool isConnecting;
  final Offset? connectingFrom;
  final Offset? connectingTo;
  /// یال فعال در اجرای زنده (از آخرین نود تکمیل‌شده به نود در حال اجرا)
  final String? liveEdgeSourceNodeId;
  final String? liveEdgeTargetNodeId;
  /// یال‌های روی مسیر `executed_nodes` در تاریخچه
  final Set<String> historyHighlightedConnectionIds;
  /// ۰…۱ برای ضخامت/شفافیت پالس روی یال زنده (اختیاری)
  final double? liveEdgePulseT;

  WorkflowConnectionPainter({
    required this.connections,
    required this.nodePositions,
    this.selectedConnectionId,
    this.isConnecting = false,
    this.connectingFrom,
    this.connectingTo,
    this.liveEdgeSourceNodeId,
    this.liveEdgeTargetNodeId,
    this.liveEdgePulseT,
    this.historyHighlightedConnectionIds = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final defaultPaint = Paint()
      ..color = Colors.blue.shade400
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final selectedPaint = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final historyPathPaint = Paint()
      ..color = const Color(0xFFF9A825)
      ..strokeWidth = 3.4
      ..style = PaintingStyle.stroke;

    // رسم خطوط اتصال موجود
    for (final connection in connections) {
      final sourceNodePos = nodePositions[connection.sourceNodeId];
      final targetNodePos = nodePositions[connection.targetNodeId];

      if (sourceNodePos == null || targetNodePos == null) continue;

      // محاسبه موقعیت connection points
      final sourceSide = 'bottom'; // از پایین source node
      final targetSide = 'top'; // به بالای target node
      
      final sourcePoint = _getConnectionPoint(sourceNodePos, sourceSide);
      final targetPoint = _getConnectionPoint(targetNodePos, targetSide);

      final isLiveEdge = liveEdgeSourceNodeId != null &&
          liveEdgeTargetNodeId != null &&
          connection.sourceNodeId == liveEdgeSourceNodeId &&
          connection.targetNodeId == liveEdgeTargetNodeId;
      final isHistoryEdge = historyHighlightedConnectionIds.contains(connection.id);
      final isSelected = connection.id == selectedConnectionId;

      final Paint paint;
      if (isLiveEdge) {
        final pulse = liveEdgePulseT;
        final wave = pulse != null
            ? (0.5 + 0.5 * math.sin(pulse * math.pi * 2))
            : 1.0;
        final strokeW = 3.6 + 1.9 * wave;
        final alpha = 0.72 + 0.28 * wave;
        paint = Paint()
          ..color = const Color(0xFF00897B).withValues(alpha: alpha)
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke;
      } else if (isHistoryEdge) {
        paint = historyPathPaint;
      } else if (isSelected) {
        paint = selectedPaint;
      } else {
        paint = defaultPaint;
      }

      _drawConnection(canvas, sourcePoint, targetPoint, paint);
    }

    // رسم خط اتصال موقتی (در حال کشیدن)
    if (isConnecting && connectingFrom != null && connectingTo != null) {
      final tempPaint = Paint()
        ..color = Colors.blue.shade300
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      _drawDashedConnection(canvas, connectingFrom!, connectingTo!, tempPaint);
    }
  }

  /// محاسبه موقعیت connection point برای یک node
  Offset _getConnectionPoint(Offset nodePosition, String side) {
    return WorkflowConstants.getConnectionPoint(nodePosition, side);
  }

  /// رسم یک خط اتصال با Bezier curve
  void _drawConnection(Canvas canvas, Offset start, Offset end, Paint paint) {
    // تعیین جهت اتصال
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    
    // محاسبه control points برای Bezier curve با توجه به جهت
    double horizontalOffset;
    double verticalOffset;
    
    if (dx.abs() > dy.abs()) {
      // اتصال افقی - offset افقی بیشتر
      horizontalOffset = math.max(dx.abs() * 0.5, 80.0);
      verticalOffset = 0.0;
    } else {
      // اتصال عمودی - offset عمودی بیشتر
      horizontalOffset = 0.0;
      verticalOffset = math.max(dy.abs() * 0.5, 80.0);
    }
    
    final cp1 = Offset(
      start.dx + (dx > 0 ? horizontalOffset : -horizontalOffset),
      start.dy + (dy > 0 ? verticalOffset : -verticalOffset),
    );
    final cp2 = Offset(
      end.dx - (dx > 0 ? horizontalOffset : -horizontalOffset),
      end.dy - (dy > 0 ? verticalOffset : -verticalOffset),
    );

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    canvas.drawPath(path, paint);

    // رسم فلش در انتهای خط
    _drawArrow(canvas, end, cp2, paint);
  }

  /// رسم یک خط اتصال خط چین با Bezier curve
  void _drawDashedConnection(Canvas canvas, Offset start, Offset end, Paint paint) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    // محاسبه control points برای Bezier curve
    final dx = end.dx - start.dx;
    
    // فاصله control point ها از start/end (حداقل 50 پیکسل)
    final controlPointOffset = math.max(dx.abs() * 0.5, 50.0);
    
    final cp1 = Offset(
      start.dx + controlPointOffset,
      start.dy,
    );
    final cp2 = Offset(
      end.dx - controlPointOffset,
      end.dy,
    );

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    // رسم خط چین با استفاده از dashPath
    final dashPath = Path();
    const dashWidth = 5.0;
    const dashSpace = 5.0;
    final metrics = path.computeMetrics();
    
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);

    // رسم فلش در انتهای خط
    _drawArrow(canvas, end, cp2, paint);
  }

  /// رسم فلش در انتهای خط
  void _drawArrow(Canvas canvas, Offset end, Offset controlPoint, Paint paint) {
    final angle = _calculateAngle(controlPoint, end);
    const arrowLength = 12.0;
    const arrowWidth = 8.0;
    const arrowAngle = 0.6; // رادیان - زاویه بزرگ‌تر برای فلش واضح‌تر

    // رسم فلش به صورت مثلث
    final arrowPath = Path();
    final arrowPoint1 = Offset(
      end.dx - arrowLength * math.cos(angle - arrowAngle),
      end.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final arrowPoint2 = Offset(
      end.dx - arrowLength * math.cos(angle + arrowAngle),
      end.dy - arrowLength * math.sin(angle + arrowAngle),
    );

    arrowPath.moveTo(end.dx, end.dy);
    arrowPath.lineTo(arrowPoint1.dx, arrowPoint1.dy);
    arrowPath.lineTo(arrowPoint2.dx, arrowPoint2.dy);
    arrowPath.close();

    // استفاده از رنگ یکسان برای فلش
    final arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(arrowPath, arrowPaint);
    
    // اضافه کردن outline برای وضوح بیشتر
    final outlinePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(arrowPath, outlinePaint);
  }

  /// محاسبه زاویه بین دو نقطه
  double _calculateAngle(Offset start, Offset end) {
    return (end - start).direction;
  }

  @override
  bool shouldRepaint(WorkflowConnectionPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.nodePositions != nodePositions ||
        oldDelegate.selectedConnectionId != selectedConnectionId ||
        oldDelegate.isConnecting != isConnecting ||
        oldDelegate.connectingFrom != connectingFrom ||
        oldDelegate.connectingTo != connectingTo ||
        oldDelegate.liveEdgeSourceNodeId != liveEdgeSourceNodeId ||
        oldDelegate.liveEdgeTargetNodeId != liveEdgeTargetNodeId ||
        oldDelegate.liveEdgePulseT != liveEdgePulseT ||
        oldDelegate.historyHighlightedConnectionIds != historyHighlightedConnectionIds;
  }
}

