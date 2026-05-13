import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_models.dart';
import '../../utils/error_extractor.dart';
import '../../utils/workflow_basalam_guard.dart';
import '../../utils/workflow_constants.dart';

/// Widget برای نمایش یک node در workflow
class WorkflowNodeWidget extends StatelessWidget {
  final WorkflowNodeModel node;
  /// اگر [false] باشد و نود باسلام باشد، آیکون هشدار در هدر نمایش داده می‌شود.
  final bool basalamPluginActive;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onPositionChanged;
  final VoidCallback? onStartConnection;
  final VoidCallback? onEndConnection;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset>? onConnectionDragUpdate;
  /// وقتی کشیدن سیم از output رها می‌شود (canvas روی PanEnd نمی‌گیرد چون gesture را connection point برده)
  final VoidCallback? onConnectionDragEnd;
  final double zoomLevel;
  final bool highlightConnectionPoints; // برای highlight کردن connection points قابل اتصال
  final ValueChanged<Offset>? onDeltaChanged; // برای ارسال موقعیت global در canvas coordinates
  final List<String>? validationErrors; // خطاهای اعتبارسنجی
  final WorkflowNodeRunPhase runPhase;

  const WorkflowNodeWidget({
    super.key,
    required this.node,
    this.basalamPluginActive = true,
    this.isSelected = false,
    this.runPhase = WorkflowNodeRunPhase.idle,
    this.onTap,
    this.onPositionChanged,
    this.onStartConnection,
    this.onEndConnection,
    this.onLongPress,
    this.onConnectionDragUpdate,
    this.onConnectionDragEnd,
    this.zoomLevel = 1.0,
    this.highlightConnectionPoints = false,
    this.onDeltaChanged,
    this.validationErrors,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final color = _getNodeColor(node.type, theme, node.key);

      // بررسی اعتبار موقعیت
      final validPosition = _isValidPosition(node.position) 
          ? node.position 
          : const Offset(200, 200);
      
      // ذخیره مقادیر مورد نیاز در local variables برای استفاده در closures
      final nodePosition = validPosition;
      final nodeTypeForClosure = node.type;
      final nodeLabelForClosure = node.label;
      final themeForClosure = theme;
      final colorForClosure = color;
      final isSelectedForClosure = isSelected;
      
      // ایجاد icon data و text style
      final iconData = _getNodeIcon(nodeTypeForClosure, node.key);
      final textStyle = themeForClosure.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorForClosure,
      );
      
      // ایجاد border color (اجرای زنده اولویت بعد از خطای اعتبارسنجی)
      final hasErrors = validationErrors != null && validationErrors!.isNotEmpty;
      final Color borderColor;
      final double borderWidth;
      if (hasErrors) {
        borderColor = Colors.red;
        borderWidth = (isSelectedForClosure || hasErrors) ? 3.0 : 2.0;
      } else {
        switch (runPhase) {
          case WorkflowNodeRunPhase.running:
            borderColor = themeForClosure.colorScheme.primary;
            borderWidth = 3.5;
            break;
          case WorkflowNodeRunPhase.success:
            borderColor = Colors.green.shade700;
            borderWidth = 3.0;
            break;
          case WorkflowNodeRunPhase.error:
            borderColor = Colors.red.shade800;
            borderWidth = 3.0;
            break;
          case WorkflowNodeRunPhase.historyReplay:
            borderColor = Colors.amber.shade800;
            borderWidth = 3.0;
            break;
          case WorkflowNodeRunPhase.idle:
            borderColor =
                isSelectedForClosure ? themeForClosure.colorScheme.primary : colorForClosure;
            borderWidth = (isSelectedForClosure || hasErrors) ? 3.0 : 2.0;
            break;
        }
      }
      
      // ایجاد surface color
      final surfaceColor = themeForClosure.colorScheme.surface;
      
      // ایجاد header background color
      final headerBackgroundColor = colorForClosure.withOpacity(0.2);
      
      final isTrigger = _isTriggerNode(nodeTypeForClosure);
      final isNotTrigger = !isTrigger;

      final showBasalamInactiveHint =
          !basalamPluginActive && workflowNodeReferencesBasalam(node);

      // ساخت widget بدون Builder برای جلوگیری از مشکل closure
      final stackWidget = _buildStackWidget(
        context: context,
        isTrigger: isTrigger,
        isNotTrigger: isNotTrigger,
        theme: theme,
        color: color,
        borderColor: borderColor,
        borderWidth: borderWidth,
        surfaceColor: surfaceColor,
        headerBackgroundColor: headerBackgroundColor,
        iconData: iconData,
        textStyle: textStyle,
        hasErrors: hasErrors,
        runPhase: runPhase,
        showBasalamPluginInactiveHint: showBasalamInactiveHint,
      );
      
      return Positioned(
        left: validPosition.dx,
        top: validPosition.dy,
        child: RepaintBoundary(
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            onPanStart: (details) {
              // علامت‌گذاری شروع drag
              if (onDeltaChanged != null) {
                onDeltaChanged?.call(Offset.zero); // سیگنال شروع drag
              }
            },
            onPanUpdate: (details) {
              if (onPositionChanged != null) {
                // استفاده مستقیم از delta (adjust شده با zoom)
                final adjustedDelta = details.delta / (zoomLevel > 0 ? zoomLevel : 1.0);
                final newPosition = node.position + adjustedDelta;
                onPositionChanged?.call(newPosition);
              }
            },
            child: stackWidget,
          ),
        ),
      );
    } catch (e, stackTrace) {
      // در صورت خطا، یک widget placeholder برگردان
      debugPrint('خطا در ساخت WorkflowNodeWidget برای node ${node.id}: $e');
      debugPrint('StackTrace: $stackTrace');
      return Positioned(
        left: _isValidPosition(node.position) ? node.position.dx : 200,
        top: _isValidPosition(node.position) ? node.position.dy : 200,
        child: Container(
          width: 180,
          height: 100,
          color: Colors.red.withOpacity(0.2),
          child: const Center(
            child: Icon(Icons.error, color: Colors.red),
          ),
        ),
      );
    }
  }

  /// بررسی اعتبار یک موقعیت
  bool _isValidPosition(Offset position) {
    return position.dx.isFinite && 
           position.dy.isFinite &&
           !position.dx.isNaN && 
           !position.dy.isNaN;
  }

  /// بررسی اینکه آیا node از نوع trigger است یا نه
  /// این متد به صورت safe enum را چک می‌کند تا مشکل type checking در Flutter Web نداشته باشیم
  bool _isTriggerNode(WorkflowNodeType type) {
    try {
      // استفاده از switch برای جلوگیری از مشکل در Flutter Web
      switch (type) {
        case WorkflowNodeType.trigger:
          return true;
        case WorkflowNodeType.action:
        case WorkflowNodeType.condition:
        case WorkflowNodeType.loop:
          return false;
      }
    } catch (e) {
      debugPrint('🔴 [_isTriggerNode] خطا در بررسی نوع: $e');
      return false; // در صورت خطا، فرض کنیم trigger نیست
    }
  }

  /// ساخت Stack widget با connection points
  Widget _buildStackWidget({
    required BuildContext context,
    required bool isTrigger,
    required bool isNotTrigger,
    required ThemeData theme,
    required Color color,
    required Color borderColor,
    required double borderWidth,
    required Color surfaceColor,
    required Color headerBackgroundColor,
    required IconData iconData,
    required TextStyle? textStyle,
    required bool hasErrors,
    required WorkflowNodeRunPhase runPhase,
    required bool showBasalamPluginInactiveHint,
  }) {
    try {
      // ایجاد لیست connection points
      final connectionPoints = <Widget>[];
      
      // پایین (output) - برای همه
      connectionPoints.add(
        Positioned(
          bottom: -8,
          left: WorkflowConstants.nodeWidth / 2 - 8,
          child: _buildConnectionPoint(
            context,
            isOutput: true,
            isHighlighted: false,
            onTap: onStartConnection,
            onConnectionDragUpdate: onConnectionDragUpdate,
            onConnectionDragEnd: onConnectionDragEnd,
          ),
        ),
      );
      
      // بالا (input) - فقط برای action/condition/loop
      if (isNotTrigger) {
        connectionPoints.add(
          Positioned(
            top: -8,
            left: WorkflowConstants.nodeWidth / 2 - 8,
            child: _buildConnectionPoint(
              context,
              isOutput: false,
              isHighlighted: highlightConnectionPoints,
              onTap: onEndConnection,
              onConnectionDragUpdate: onConnectionDragUpdate,
            ),
          ),
        );
      }
      
      // راست (output) - فقط برای action/condition/loop
      if (isNotTrigger) {
        connectionPoints.add(
          Positioned(
            top: WorkflowConstants.nodeHeight / 2 - 8,
            right: -8,
            child: _buildConnectionPoint(
              context,
              isOutput: true,
              isHighlighted: false,
              onTap: onStartConnection,
              onConnectionDragUpdate: onConnectionDragUpdate,
              onConnectionDragEnd: onConnectionDragEnd,
            ),
          ),
        );
      }
      
      // چپ (input) - فقط برای trigger
      if (isTrigger) {
        connectionPoints.add(
          Positioned(
            top: WorkflowConstants.nodeHeight / 2 - 8,
            left: -8,
            child: _buildConnectionPoint(
              context,
              isOutput: false,
              isHighlighted: highlightConnectionPoints,
              onTap: onEndConnection,
              onConnectionDragUpdate: onConnectionDragUpdate,
            ),
          ),
        );
      }
      
      // ساخت Container اصلی
      final mainContainer = Container(
        width: WorkflowConstants.nodeWidth,
        height: WorkflowConstants.nodeHeight,
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: headerBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    iconData,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.label,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showBasalamPluginInactiveHint)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Tooltip(
                        message: AppLocalizations.of(context).workflowBasalamPluginInactiveHint,
                        child: Icon(
                          Icons.extension_off,
                          size: 16,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Body
            const Expanded(
              child: SizedBox(),
            ),
          ],
        ),
      );
      
      // ساخت لیست children
      final children = <Widget>[
        mainContainer,
        ...connectionPoints,
      ];
      
      // اضافه کردن error badge اگر خطا وجود دارد
      if (validationErrors != null && validationErrors!.isNotEmpty) {
        children.add(
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.error,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        );
      }
      
      // اضافه کردن comment badge اگر یادداشت وجود دارد
      if (node.comment != null && node.comment!.isNotEmpty) {
        children.add(
          Positioned(
            top: -8,
            left: -8,
            child: Tooltip(
              message: node.comment!,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.note,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        );
      }

      if (!hasErrors && runPhase == WorkflowNodeRunPhase.running) {
        children.add(
          Positioned(
            top: 6,
            right: 6,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      if (!hasErrors && runPhase == WorkflowNodeRunPhase.success) {
        children.add(
          Positioned(
            top: 4,
            right: 4,
            child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
          ),
        );
      }
      if (!hasErrors && runPhase == WorkflowNodeRunPhase.error) {
        children.add(
          Positioned(
            top: 4,
            right: 4,
            child: Icon(Icons.cancel, color: Colors.red.shade800, size: 20),
          ),
        );
      }
      if (!hasErrors && runPhase == WorkflowNodeRunPhase.historyReplay) {
        children.add(
          Positioned(
            top: 4,
            right: 4,
            child: Icon(Icons.history, color: Colors.amber.shade900, size: 20),
          ),
        );
      }
      
      // برگرداندن Stack
      return Stack(
        clipBehavior: Clip.none,
        children: children,
      );
    } catch (e, stackTrace) {
      debugPrint('خطا در _buildStackWidget: $e');
      // در صورت خطا، یک widget ساده برگردان
      return Container(
        width: WorkflowConstants.nodeWidth,
        height: WorkflowConstants.nodeHeight,
        color: Colors.red.withOpacity(0.2),
        child: Center(
          child: Text(
            'خطا: ${ErrorExtractor.forContext(e, context)}',
            style: const TextStyle(color: Colors.red, fontSize: 10),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }

  Widget _buildConnectionPoint(
    BuildContext context, {
    required bool isOutput, // true برای output، false برای input
    bool isHighlighted = false,
    VoidCallback? onTap,
    ValueChanged<Offset>? onConnectionDragUpdate,
    VoidCallback? onConnectionDragEnd,
  }) {
    try {
      final theme = Theme.of(context);
      
      // استفاده از Builder برای گرفتن RenderBox صحیح connection point (نه parent)
      // بدون این، context.findRenderObject() والد (Stack/Node) را برمی‌گرداند و موقعیت global اشتباه محاسبه می‌شود
      Widget connectionWidget = Builder(
        builder: (connectionPointContext) => GestureDetector(
          onPanStart: (details) {
            if (isOutput && onTap != null) {
              onTap(); // شروع اتصال از output point
            }
          },
          onPanUpdate: (details) {
            if (isOutput && onConnectionDragUpdate != null) {
              final RenderBox? box = connectionPointContext.findRenderObject() as RenderBox?;
              if (box != null) {
                final globalPos = box.localToGlobal(details.localPosition);
                onConnectionDragUpdate!(globalPos);
              }
            }
          },
          onPanEnd: (details) {
            if (isOutput) {
              onConnectionDragEnd?.call(); // رها کردن سیم از output؛ canvas روی PanEnd نمی‌گیرد
            } else if (onTap != null) {
              onTap(); // کامل کردن اتصال در input point
            }
          },
          child: _buildConnectionPointContainer(
            theme: theme,
            isHighlighted: isHighlighted,
            isOutput: isOutput,
          ),
        ),
      );
      
      // اضافه کردن MouseRegion فقط اگر لازم باشد
      try {
        final cursor = isOutput ? SystemMouseCursors.grab : SystemMouseCursors.click;
        connectionWidget = MouseRegion(
          cursor: cursor,
          child: connectionWidget,
        );
      } catch (e) {
        // Ignore cursor error, continue without it
      }
      
      return connectionWidget;
    } catch (e, stackTrace) {
      debugPrint('خطا در _buildConnectionPoint: $e');
      // در صورت خطا، یک widget ساده برگردان
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red,
        ),
      );
    }
  }

  Widget _buildConnectionPointContainer({
    required ThemeData theme,
    required bool isHighlighted,
    required bool isOutput,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isHighlighted ? WorkflowConstants.connectionPointHighlightSize : WorkflowConstants.connectionPointSize,
      height: isHighlighted ? WorkflowConstants.connectionPointHighlightSize : WorkflowConstants.connectionPointSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isHighlighted ? Colors.green : theme.colorScheme.primary,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: isHighlighted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isHighlighted ? Colors.green : Colors.black).withOpacity(isHighlighted ? 0.5 : 0.2),
            blurRadius: isHighlighted ? 8 : 4,
            offset: const Offset(0, 2),
            spreadRadius: isHighlighted ? 2 : 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: isHighlighted ? 10 : 8,
        height: isHighlighted ? 10 : 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
        ),
      ),
    );
  }

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme, String? nodeKey) {
    if (type == WorkflowNodeType.action && nodeKey == 'send_business_sms') {
      return Colors.teal.shade700;
    }
    if (type == WorkflowNodeType.action && nodeKey == 'send_email') {
      return Colors.indigo.shade600;
    }
    switch (type) {
      case WorkflowNodeType.trigger:
        return Colors.green;
      case WorkflowNodeType.action:
        return theme.colorScheme.primary;
      case WorkflowNodeType.condition:
        return Colors.orange;
      case WorkflowNodeType.loop:
        return Colors.purple;
    }
  }

  IconData _getNodeIcon(WorkflowNodeType type, String? nodeKey) {
    if (type == WorkflowNodeType.action) {
      switch (nodeKey) {
        case 'send_business_sms':
          return Icons.sms_outlined;
        case 'send_email':
          return Icons.email_outlined;
        case 'send_telegram':
          return Icons.send;
        case 'send_bale':
          return Icons.chat;
        case 'http_request':
          return Icons.http;
        default:
          return Icons.play_arrow;
      }
    }
    switch (type) {
      case WorkflowNodeType.trigger:
        return Icons.bolt;
      case WorkflowNodeType.action:
        return Icons.play_arrow;
      case WorkflowNodeType.condition:
        return Icons.code;
      case WorkflowNodeType.loop:
        return Icons.loop;
    }
  }
}
