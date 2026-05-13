import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/error_extractor.dart';
import 'package:flutter/services.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../utils/workflow_constants.dart';
import 'workflow_connection_painter.dart';
import 'workflow_node_widget.dart';

/// Canvas اصلی برای نمایش و ویرایش workflow
class WorkflowCanvas extends StatefulWidget {
  final WorkflowEditorState state;
  /// اگر [false] باشد، روی نودهای وابسته به باسلام هشدار کوچک نمایش داده می‌شود.
  final bool basalamPluginActive;
  final Function(WorkflowNodeModel)? onNodeTap;
  final Function(WorkflowConnectionModel)? onConnectionTap;
  final Future<void> Function(WorkflowNodeModel, Offset)? onNodeLongPress;

  const WorkflowCanvas({
    super.key,
    required this.state,
    this.basalamPluginActive = true,
    this.onNodeTap,
    this.onConnectionTap,
    this.onNodeLongPress,
  });

  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  Offset? _lastPanPosition;
  Offset? _connectingToPosition;
  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _interactiveViewerKey = GlobalKey();
  String? _draggingNodeId; // ID نودی که در حال drag است
  bool _isDragStarted = false; // آیا drag شروع شده است
  AnimationController? _liveEdgePulseController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    widget.state.addListener(_onStateChanged);
    _syncLiveEdgePulse();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _liveEdgePulseController?.removeListener(_pulseTick);
    _liveEdgePulseController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _pulseTick() {
    if (mounted) setState(() {});
  }

  void _syncLiveEdgePulse() {
    final need = widget.state.liveActiveEdgeSourceNodeId != null &&
        widget.state.liveActiveEdgeTargetNodeId != null;

    if (need && _liveEdgePulseController == null) {
      _liveEdgePulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 780),
      )
        ..repeat(reverse: true)
        ..addListener(_pulseTick);
    } else if (!need && _liveEdgePulseController != null) {
      _liveEdgePulseController!.removeListener(_pulseTick);
      _liveEdgePulseController!.dispose();
      _liveEdgePulseController = null;
    }
  }

  void _onStateChanged() {
    _syncLiveEdgePulse();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    try {
      // محاسبه موقعیت node ها (با در نظر گیری zoom و pan)
      final nodePositions = <String, Offset>{};
      for (final node in widget.state.nodes) {
        // بررسی اعتبار موقعیت
        if (_isValidPosition(node.position)) {
          nodePositions[node.id] = node.position;
        } else {
          // اگر موقعیت نامعتبر است، از موقعیت پیش‌فرض استفاده کن
          nodePositions[node.id] = const Offset(200, 200);
        }
      }

      // محاسبه موقعیت اتصال موقتی
      Offset? connectingFrom;
      Offset? connectingTo;
      if (widget.state.isConnecting) {
        final fromNode = widget.state.getNodeById(widget.state.connectingFromNodeId ?? '');
        if (fromNode != null && _isValidPosition(fromNode.position)) {
          // استفاده از connection point در پایین node
          connectingFrom = WorkflowConstants.getConnectionPoint(fromNode.position, 'bottom');
        }
        final connectingPos = widget.state.connectingPosition ?? _connectingToPosition;
        if (connectingPos != null && _isValidPosition(connectingPos)) {
          connectingTo = connectingPos;
        }
      }

    return InteractiveViewer(
      key: _interactiveViewerKey,
      transformationController: _transformationController,
      minScale: WorkflowConstants.minZoom,
      maxScale: WorkflowConstants.maxZoom,
      panEnabled: !widget.state.isConnecting && _draggingNodeId == null, // غیرفعال کردن pan هنگام اتصال یا drag نود
      scaleEnabled: !widget.state.isConnecting && _draggingNodeId == null,
      onInteractionUpdate: (details) {
        if (details.pointerCount == 1 && !widget.state.isConnecting && _draggingNodeId == null) {
          // Pan - فقط وقتی که در حال اتصال و drag نیستیم
          widget.state.updateViewport(
            Offset(
              _transformationController.value.getTranslation().x,
              _transformationController.value.getTranslation().y,
            ),
          );
          widget.state.updateZoom(_transformationController.value.getMaxScaleOnAxis());
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent, // اجازه می‌دهد child ها events را بگیرند
        onPanStart: (details) {
          _lastPanPosition = details.localPosition;
          
          // اگر Shift فشار نشده و روی node نیستیم، شروع selection box
          if (!HardwareKeyboard.instance.isShiftPressed && 
              !widget.state.isConnecting && _draggingNodeId == null) {
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            if (!_isOnNode(canvasPosition)) {
              widget.state.startSelection(canvasPosition);
            }
          }
        },
        onPanUpdate: (details) {
          if (widget.state.isConnecting) {
            // تبدیل موقعیت با در نظر گیری transformation
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            _connectingToPosition = canvasPosition;
            widget.state.updateConnectingPosition(canvasPosition);
            setState(() {}); // Force rebuild برای نمایش خط
          } else if (widget.state.isSelecting) {
            // به‌روزرسانی selection box
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            widget.state.updateSelection(canvasPosition);
          } else {
            // Pan canvas
            final delta = details.localPosition - (_lastPanPosition ?? Offset.zero);
            _lastPanPosition = details.localPosition;
            // این کار توسط InteractiveViewer انجام می‌شود
          }
        },
        onPanEnd: (details) async {
          if (widget.state.isConnecting) {
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            final droppedNode = _findNodeAtPosition(canvasPosition);
            final fromNodeId = widget.state.connectingFromNodeId;
            String? sourceOutputId;
            if (fromNodeId != null && droppedNode != null && mounted) {
              final fromNode = widget.state.getNodeById(fromNodeId);
              if (fromNode?.type == WorkflowNodeType.condition) {
                sourceOutputId = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('شاخه شرط'),
                    content: const Text(
                      'این اتصال به شاخه برست یا نادرست نود شرط متصل می‌شود:',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('انصراف'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop('false'),
                        child: const Text('نادرست'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop('true'),
                        child: const Text('برست'),
                      ),
                    ],
                  ),
                );
                if (sourceOutputId == null && mounted) {
                  widget.state.cancelConnection();
                  _connectingToPosition = null;
                  return;
                }
              } else if (fromNode?.type == WorkflowNodeType.loop) {
                sourceOutputId = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('خروجی حلقه'),
                    content: const Text(
                      '«هر تکرار»: نودهای داخل حلقه (برای هر آیتم اجرا می‌شوند).\n'
                      '«پس از پایان»: نودهایی که بعد از اتمام همهٔ تکرارها اجرا شوند (مثلاً گزارش نهایی).',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('انصراف'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop('each'),
                        child: const Text('هر تکرار'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop('done'),
                        child: const Text('پس از پایان'),
                      ),
                    ],
                  ),
                );
                if (sourceOutputId == null && mounted) {
                  widget.state.cancelConnection();
                  _connectingToPosition = null;
                  return;
                }
              }
            }
            widget.state.endConnection(droppedNode?.id, sourceOutputId: sourceOutputId);
            _connectingToPosition = null;
          } else if (widget.state.isSelecting) {
            widget.state.endSelection();
          } else if (_draggingNodeId != null) {
            // اعمال snap to grid در پایان drag
            final node = widget.state.getNodeById(_draggingNodeId!);
            if (node != null) {
              widget.state.snapNodeToGrid(_draggingNodeId!);
            }
          }
          _lastPanPosition = null;
          _draggingNodeId = null;
          _isDragStarted = false;
        },
        onTapUp: (details) {
          // لغو انتخاب
          final canvasPosition = _localToCanvasCoordinates(details.localPosition);
          if (!_isOnNode(canvasPosition)) {
            widget.state.selectNode(null);
            widget.state.selectConnection(null);
          }
        },
        child: Container(
          key: _canvasKey,
          color: Colors.grey.shade50,
          child: Stack(
            children: [
              // Grid background
              if (widget.state.showGrid)
                RepaintBoundary(
                  child: _buildGrid(widget.state.gridSize > 0 ? widget.state.gridSize : WorkflowConstants.gridSize),
                ),
              // Connections (رسم قبل از nodes تا زیر آنها نباشند)
              RepaintBoundary(
                child: CustomPaint(
                  painter: WorkflowConnectionPainter(
                    connections: widget.state.connections,
                    nodePositions: nodePositions,
                    selectedConnectionId: widget.state.selectedConnectionId,
                    isConnecting: widget.state.isConnecting,
                    connectingFrom: connectingFrom,
                    connectingTo: connectingTo,
                    liveEdgeSourceNodeId: widget.state.liveActiveEdgeSourceNodeId,
                    liveEdgeTargetNodeId: widget.state.liveActiveEdgeTargetNodeId,
                    liveEdgePulseT: _liveEdgePulseController?.value,
                    historyHighlightedConnectionIds: widget.state.historyPathConnectionIds,
                  ),
                  size: Size.infinite,
                ),
              ),
              // Selection Box
              if (widget.state.isSelecting && 
                  widget.state.selectionStart != null && 
                  widget.state.selectionEnd != null)
                CustomPaint(
                  painter: SelectionBoxPainter(
                    start: widget.state.selectionStart!,
                    end: widget.state.selectionEnd!,
                  ),
                  size: Size.infinite,
                ),
              // Nodes (بالاتر از connections)
              ...widget.state.nodes.where((node) {
                // فیلتر کردن نودهایی با موقعیت نامعتبر
                return _isValidPosition(node.position);
              }).map((node) {
                try {
                  final isSelected = widget.state.selectedNodeId == node.id || 
                                      widget.state.selectedNodeIds.contains(node.id);
                  
                  // بررسی اینکه آیا این node قابل اتصال است (برای highlight)
                  final canConnect = _canConnectToNode(node);
                  
                  // اطمینان از اینکه موقعیت معتبر است
                  final validPosition = _isValidPosition(node.position) 
                      ? node.position 
                      : const Offset(200, 200);
                  
                  final nodeToDisplay = node.position != validPosition
                      ? node.copyWith(position: validPosition)
                      : node;
                  
                  final validationErrors = widget.state.validateNode(node.id);
                  
                  return WorkflowNodeWidget(
                    key: ValueKey(node.id),
                    node: nodeToDisplay,
                    basalamPluginActive: widget.basalamPluginActive,
                    isSelected: isSelected,
                    runPhase: widget.state.nodeRunPhase(node.id),
                    zoomLevel: widget.state.zoomLevel > 0 ? widget.state.zoomLevel : 1.0,
                    highlightConnectionPoints: widget.state.isConnecting && canConnect,
                    validationErrors: validationErrors.isNotEmpty ? validationErrors : null,
                      onTap: () {
                        // بررسی کلیدهای Shift و Ctrl
                        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                        final isCtrlPressed = HardwareKeyboard.instance.isControlPressed || 
                                              HardwareKeyboard.instance.isMetaPressed;
                        
                        if (isCtrlPressed) {
                          // Ctrl+Click: toggle selection
                          widget.state.selectNode(node.id, toggle: true);
                        } else if (isShiftPressed) {
                          // Shift+Click: add to selection
                          widget.state.selectNode(node.id, addToSelection: true);
                        } else {
                          // کلیک معمولی
                          widget.state.selectNode(node.id);
                          widget.onNodeTap?.call(node);
                        }
                      },
                      onLongPress: () async {
                        widget.state.selectNode(node.id);
                        if (widget.onNodeLongPress != null) {
                          try {
                            // استفاده از موقعیت node برای نمایش context menu
                            final position = WorkflowConstants.getNodeCenter(validPosition);
                            await widget.onNodeLongPress!.call(node, position);
                          } catch (e) {
                            debugPrint('خطا در onLongPress: $e');
                          }
                        }
                      },
                      onDeltaChanged: (signal) {
                        // سیگنال شروع drag
                        if (signal == Offset.zero) {
                          _draggingNodeId = node.id;
                          _isDragStarted = true;
                        }
                      },
                      onPositionChanged: (newPosition) {
                        if (_isValidPosition(newPosition)) {
                          if (_isDragStarted && _draggingNodeId == node.id) {
                            // در حین drag از updateWithoutSnap استفاده می‌کنیم
                            widget.state.updateNodePositionWithoutSnap(node.id, newPosition);
                          } else {
                            widget.state.updateNodePosition(node.id, newPosition);
                          }
                        }
                      },
                      onStartConnection: () {
                        widget.state.startConnection(node.id);
                      },
                      onEndConnection: () async {
                        final fromNodeId = widget.state.connectingFromNodeId;
                        String? sourceOutputId;
                        if (fromNodeId != null && mounted) {
                          final fromNode = widget.state.getNodeById(fromNodeId);
                          if (fromNode?.type == WorkflowNodeType.condition) {
                            sourceOutputId = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('شاخه شرط'),
                                content: const Text(
                                  'این اتصال به شاخه برست یا نادرست نود شرط متصل می‌شود:',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('انصراف'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop('false'),
                                    child: const Text('نادرست'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop('true'),
                                    child: const Text('برست'),
                                  ),
                                ],
                              ),
                            );
                            if (sourceOutputId == null && mounted) {
                              widget.state.cancelConnection();
                              return;
                            }
                          }
                        }
                        if (mounted) {
                          widget.state.endConnection(node.id, sourceOutputId: sourceOutputId);
                        }
                      },
                      onConnectionDragUpdate: (globalPosition) {
                        try {
                          // تبدیل موقعیت global به canvas coordinates
                          final canvasPosition = _globalToCanvasCoordinates(globalPosition);
                          if (_isValidPosition(canvasPosition)) {
                            widget.state.updateConnectingPosition(canvasPosition);
                            setState(() {}); // Force rebuild
                          }
                        } catch (e) {
                          debugPrint('خطا در onConnectionDragUpdate: $e');
                        }
                      },
                      onConnectionDragEnd: _handleConnectionDragEnd,
                  );
                } catch (e, stackTrace) {
                  debugPrint('خطا در ساخت widget برای node ${node.id}: $e');
                  // برگرداندن یک placeholder widget برای جلوگیری از crash
                  return SizedBox(
                    key: ValueKey('error_${node.id}'),
                    width: 0,
                    height: 0,
                  );
                }
              }),
            ],
          ),
        ),
      ),
    );
    } catch (e, stackTrace) {
      debugPrint('خطا در ساخت WorkflowCanvas: $e');
      debugPrint('StackTrace: $stackTrace');
      // برگرداندن یک widget خطا برای جلوگیری از صفحه سفید
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '${AppLocalizations.of(context).workflowErrorDisplay}: ${ErrorExtractor.forContext(e, context)}',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {});
              },
              child: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      );
    }
  }

  /// بررسی اعتبار یک موقعیت (نه NaN و نه Infinity)
  bool _isValidPosition(Offset position) {
    return position.dx.isFinite && 
           position.dy.isFinite &&
           !position.dx.isNaN && 
           !position.dy.isNaN;
  }

  Widget _buildGrid(double gridSize) {
    return CustomPaint(
      painter: GridPainter(
        gridSize: gridSize,
        showGrid: true,
      ),
      size: Size.infinite,
    );
  }

  WorkflowNodeModel? _findNodeAtPosition(Offset position) {
    if (!_isValidPosition(position)) {
      return null;
    }
    
    try {
      for (final node in widget.state.nodes) {
        if (!_isValidPosition(node.position)) {
          continue;
        }
        final nodeRect = WorkflowConstants.getNodeRect(node.position);
        if (nodeRect.contains(position)) {
          return node;
        }
      }
    } catch (e) {
      debugPrint('خطا در _findNodeAtPosition: $e');
    }
    return null;
  }

  bool _isOnNode(Offset position) {
    return _findNodeAtPosition(position) != null;
  }

  /// وقتی کشیدن سیم از output رها می‌شود؛ canvas روی PanEnd نمی‌گیرد چون gesture را connection point برده
  Future<void> _handleConnectionDragEnd() async {
    if (!widget.state.isConnecting) return;
    final canvasPosition = widget.state.connectingPosition ?? _connectingToPosition;
    _connectingToPosition = null;
    final droppedNode = canvasPosition != null ? _findNodeAtPosition(canvasPosition) : null;
    final fromNodeId = widget.state.connectingFromNodeId;
    String? sourceOutputId;
    if (fromNodeId != null && droppedNode != null && mounted) {
      final fromNode = widget.state.getNodeById(fromNodeId);
      if (fromNode?.type == WorkflowNodeType.condition) {
        sourceOutputId = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('شاخه شرط'),
            content: const Text(
              'این اتصال به شاخه برست یا نادرست نود شرط متصل می‌شود:',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('انصراف'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('false'),
                child: const Text('نادرست'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('true'),
                child: const Text('برست'),
              ),
            ],
          ),
        );
        if (sourceOutputId == null && mounted) {
          widget.state.cancelConnection();
          return;
        }
      }
    }
    if (mounted) {
      widget.state.endConnection(droppedNode?.id, sourceOutputId: sourceOutputId);
    }
    setState(() {});
  }

  /// تبدیل موقعیت local (نسبت به InteractiveViewer) به canvas coordinates
  Offset _localToCanvasCoordinates(Offset localPosition) {
    try {
      final matrix = _transformationController.value;
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      
      // بررسی سریع اعتبار
      if (!scale.isFinite || scale <= 0 || 
          !translation.x.isFinite || !translation.y.isFinite ||
          !localPosition.dx.isFinite || !localPosition.dy.isFinite) {
        return const Offset(0, 0);
      }
      
      // تبدیل معکوس: canvas = (viewport - translation) / scale
      final canvasX = (localPosition.dx - translation.x) / scale;
      final canvasY = (localPosition.dy - translation.y) / scale;
      
      return Offset(canvasX, canvasY);
    } catch (e) {
      return const Offset(0, 0);
    }
  }

  /// تبدیل موقعیت global به canvas coordinates
  /// canvasBox داخل InteractiveViewer است و globalToLocal خودش transform را وارونه می‌کند،
  /// پس نیازی به _localToCanvasCoordinates نیست (double transformation می‌شد)
  Offset _globalToCanvasCoordinates(Offset globalPosition) {
    try {
      final RenderBox? canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (canvasBox == null) {
        return const Offset(0, 0);
      }
      return canvasBox.globalToLocal(globalPosition);
    } catch (e) {
      return const Offset(0, 0);
    }
  }

  /// بررسی اینکه آیا می‌توان به یک node اتصال داد
  bool _canConnectToNode(WorkflowNodeModel targetNode) {
    if (!widget.state.isConnecting || widget.state.connectingFromNodeId == null) {
      return false;
    }

    final fromNode = widget.state.getNodeById(widget.state.connectingFromNodeId!);
    if (fromNode == null) return false;

    // نمی‌توان به خود node اتصال داد
    if (fromNode.id == targetNode.id) return false;

    // Trigger نمی‌تواند به trigger دیگر اتصال دهد
    if (fromNode.type == WorkflowNodeType.trigger && targetNode.type == WorkflowNodeType.trigger) {
      return false;
    }

    // اگر قبلاً این connection وجود داشته باشد، قابل اتصال نیست
    final exists = widget.state.connections.any(
      (c) => c.sourceNodeId == fromNode.id && c.targetNodeId == targetNode.id,
    );

    return !exists;
  }
}

/// Painter برای رسم grid در پس‌زمینه
class GridPainter extends CustomPainter {
  final double gridSize;
  final bool showGrid;

  GridPainter({
    this.gridSize = 20.0,
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid || gridSize <= 0) return;

    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 0.5;

    // خطوط عمودی
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // خطوط افقی
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize || oldDelegate.showGrid != showGrid;
  }
}

/// Painter برای رسم selection box
class SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  SelectionBoxPainter({
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = math.min(start.dx, end.dx);
    final right = math.max(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final bottom = math.max(start.dy, end.dy);
    
    final rect = Rect.fromLTRB(left, top, right, bottom);
    
    // رسم پس‌زمینه
    final fillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);
    
    // رسم border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(SelectionBoxPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}


