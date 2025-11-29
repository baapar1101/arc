import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'workflow_editor_models.dart';
import 'workflow_history.dart';

/// State Manager برای Workflow Editor
class WorkflowEditorState extends ChangeNotifier {
  final List<WorkflowNodeModel> _nodes = [];
  final List<WorkflowConnectionModel> _connections = [];
  // Map برای جستجوی سریع‌تر node ها
  final Map<String, WorkflowNodeModel> _nodesMap = {};
  Offset _viewportOffset = Offset.zero;
  double _zoomLevel = 1.0;
  String? _selectedNodeId;
  String? _selectedConnectionId;
  bool _isConnecting = false;
  String? _connectingFromNodeId;
  Offset? _connectingPosition; // موقعیت موقتی هنگام کشیدن خط
  bool _snapToGrid = true; // فعال/غیرفعال بودن snap to grid
  double _gridSize = 20.0; // اندازه grid برای snap

  // Metadata برای node های قابل استفاده
  List<WorkflowNodeMetadata> _triggers = [];
  List<WorkflowNodeMetadata> _actions = [];

  final _uuid = const Uuid();
  final WorkflowHistory _history = WorkflowHistory();

  // Getters
  List<WorkflowNodeModel> get nodes => List.unmodifiable(_nodes);
  List<WorkflowConnectionModel> get connections => List.unmodifiable(_connections);
  Offset get viewportOffset => _viewportOffset;
  double get zoomLevel => _zoomLevel;
  String? get selectedNodeId => _selectedNodeId;
  String? get selectedConnectionId => _selectedConnectionId;
  bool get isConnecting => _isConnecting;
  String? get connectingFromNodeId => _connectingFromNodeId;
  Offset? get connectingPosition => _connectingPosition;
  bool get snapToGrid => _snapToGrid;
  double get gridSize => _gridSize;
  List<WorkflowNodeMetadata> get triggers => List.unmodifiable(_triggers);
  List<WorkflowNodeMetadata> get actions => List.unmodifiable(_actions);
  bool get canUndo => _history.canUndo();
  bool get canRedo => _history.canRedo();

  /// بارگذاری workflow از backend format
  void loadWorkflow(Map<String, dynamic> workflowData) {
    _nodes.clear();
    _connections.clear();

    final nodesJson = workflowData['nodes'] as List<dynamic>? ?? [];
    final connectionsJson = workflowData['connections'] as List<dynamic>? ?? [];

    // تبدیل nodes
    final List<WorkflowNodeModel> loadedNodes = [];
    for (final nodeJson in nodesJson) {
      final node = WorkflowNodeModel.fromJson(nodeJson as Map<String, dynamic>);
      loadedNodes.add(node);
      _nodesMap[node.id] = node;
    }
    _nodes.addAll(loadedNodes);

    // تبدیل connections
    for (final connJson in connectionsJson) {
      final conn = WorkflowConnectionModel.fromJson(connJson as Map<String, dynamic>);
      _connections.add(conn);
    }

    // اعمال auto-layout اگر node ها موقعیت ندارند
    _applyAutoLayoutIfNeeded();

    notifyListeners();
  }

  /// اعمال auto-layout اگر لازم باشد
  void _applyAutoLayoutIfNeeded() {
    // بررسی که آیا همه node ها موقعیت دارند
    final needsLayout = _nodes.any((n) => n.position == Offset.zero) || 
                        _nodes.every((n) => n.position.dx == 0 && n.position.dy == 0);

    if (needsLayout && _nodes.isNotEmpty) {
      // استفاده از auto-layout ساده
      final positions = _calculateSimpleLayout();
      for (final node in _nodes) {
        if (positions.containsKey(node.id)) {
          final index = _nodes.indexWhere((n) => n.id == node.id);
          if (index != -1) {
            _nodes[index] = node.copyWith(position: positions[node.id]!);
          }
        }
      }
    }
  }

  /// محاسبه layout ساده
  Map<String, Offset> _calculateSimpleLayout() {
    final positions = <String, Offset>{};
    const double startX = 100.0;
    const double spacing = 200.0;
    double currentY = 100.0;

    // مرتب‌سازی: trigger ها اول
    final sortedNodes = List<WorkflowNodeModel>.from(_nodes);
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
      positions[node.id] = Offset(startX, currentY);
      currentY += spacing;
    }

    return positions;
  }

  /// تبدیل به فرمت backend
  Map<String, dynamic> toBackendFormat() {
    return {
      'nodes': _nodes.map((node) => node.toJson()).toList(),
      'connections': _connections.map((conn) => conn.toJson()).toList(),
    };
  }

  /// افزودن node جدید
  void addNode(WorkflowNodeType type, String key, String name) {
    try {
      final position = _calculateNextNodePosition();
      final node = WorkflowNodeModel(
        id: _uuid.v4(),
        type: type,
        label: name,
        position: position,
        key: key,
        config: {},
      );
      _nodes.add(node);
      _nodesMap[node.id] = node;
      
      // اضافه کردن به history
      final command = AddNodeCommand(this, node);
      command.execute();
      _history.addCommand(command);
      
      notifyListeners();
    } catch (e) {
      // در صورت خطا، listeners را اطلاع بده تا UI به‌روزرسانی شود
      notifyListeners();
      rethrow;
    }
  }

  /// افزودن node با موقعیت مشخص
  void addNodeWithPosition(WorkflowNodeModel node) {
    _nodes.add(node);
    _nodesMap[node.id] = node;
    notifyListeners();
  }

  /// محاسبه موقعیت بعدی برای node جدید
  Offset _calculateNextNodePosition() {
    try {
      if (_nodes.isEmpty) {
        final position = const Offset(200, 200);
        return _snapToGrid ? _snapToGridPosition(position) : position;
      }
      
      // پیدا کردن موقعیت آخرین node
      double maxY = 0;
      bool hasValidPosition = false;
      for (final node in _nodes) {
        if (node.position.dy.isFinite && node.position.dy > maxY) {
          maxY = node.position.dy;
          hasValidPosition = true;
        }
      }
      
      // اگر هیچ موقعیت معتبری پیدا نشد، از موقعیت پیش‌فرض استفاده کن
      if (!hasValidPosition) {
        maxY = 200;
      }
      
      // قرار دادن node جدید زیر آخرین node
      final position = Offset(200, maxY + 150);
      final snappedPosition = _snapToGrid ? _snapToGridPosition(position) : position;
      
      // اطمینان از اینکه موقعیت معتبر است
      if (!snappedPosition.dx.isFinite || !snappedPosition.dy.isFinite) {
        return const Offset(200, 200);
      }
      
      return snappedPosition;
    } catch (e) {
      // در صورت خطا، موقعیت پیش‌فرض را برگردان
      return const Offset(200, 200);
    }
  }

  /// حذف node
  void removeNode(String nodeId, {bool trackHistory = true}) {
    final node = getNodeById(nodeId);
    if (node == null) return;
    
    final relatedConnections = _connections
        .where((c) => c.sourceNodeId == nodeId || c.targetNodeId == nodeId)
        .toList();
    
    if (trackHistory) {
      // اضافه کردن به history قبل از حذف
      final command = RemoveNodeCommand(this, node, relatedConnections);
      command.execute();
      _history.addCommand(command);
    } else {
      removeNodeWithoutHistory(nodeId);
      notifyListeners();
    }
  }
  
  /// حذف node بدون history (برای undo)
  void removeNodeWithoutHistory(String nodeId) {
    _nodes.removeWhere((n) => n.id == nodeId);
    _nodesMap.remove(nodeId);
    _connections.removeWhere(
      (c) => c.sourceNodeId == nodeId || c.targetNodeId == nodeId,
    );
    if (_selectedNodeId == nodeId) {
      _selectedNodeId = null;
    }
  }
  
  /// اضافه کردن node بدون history (برای undo)
  void addNodeWithoutHistory(WorkflowNodeModel node, List<WorkflowConnectionModel> connections) {
    _nodes.add(node);
    _nodesMap[node.id] = node;
    _connections.addAll(connections);
  }

  /// به‌روزرسانی موقعیت node
  void updateNodePosition(String nodeId, Offset newPosition, {bool trackHistory = false}) {
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    if (index != -1) {
      // اعمال snap to grid
      Offset finalPosition = _snapToGrid ? _snapToGridPosition(newPosition) : newPosition;
      
      final oldPosition = _nodes[index].position;
      if (trackHistory && oldPosition != finalPosition) {
        final command = MoveNodeCommand(this, nodeId, oldPosition, finalPosition);
        command.execute();
        _history.addCommand(command);
      } else {
        _nodes[index] = _nodes[index].copyWith(position: finalPosition);
      }
      notifyListeners();
    }
  }

  /// Snap کردن موقعیت به grid
  Offset _snapToGridPosition(Offset position) {
    try {
      if (!_snapToGrid || _gridSize <= 0 || !_gridSize.isFinite) {
        return position;
      }
      
      // اطمینان از اینکه موقعیت معتبر است
      if (!position.dx.isFinite || !position.dy.isFinite) {
        return const Offset(200, 200);
      }
      
      final snappedX = (position.dx / _gridSize).round() * _gridSize;
      final snappedY = (position.dy / _gridSize).round() * _gridSize;
      
      // اطمینان از اینکه موقعیت snapped معتبر است
      if (!snappedX.isFinite || !snappedY.isFinite) {
        return position;
      }
      
      return Offset(snappedX, snappedY);
    } catch (e) {
      // در صورت خطا، موقعیت اصلی را برگردان
      return position;
    }
  }

  /// تنظیم snap to grid
  void setSnapToGrid(bool enabled) {
    _snapToGrid = enabled;
    notifyListeners();
  }

  /// تنظیم اندازه grid
  void setGridSize(double size) {
    _gridSize = size.clamp(5.0, 100.0);
    notifyListeners();
  }
  
  /// به‌روزرسانی موقعیت node بدون history (برای undo)
  void updateNodePositionWithoutHistory(String nodeId, Offset position) {
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    if (index != -1) {
      _nodes[index] = _nodes[index].copyWith(position: position);
    }
  }

  /// به‌روزرسانی config node
  void updateNodeConfig(String nodeId, Map<String, dynamic> config) {
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    if (index != -1) {
      _nodes[index] = _nodes[index].copyWith(config: config);
      notifyListeners();
    }
  }

  /// انتخاب node
  void selectNode(String? nodeId) {
    _selectedNodeId = nodeId;
    _selectedConnectionId = null;
    notifyListeners();
  }

  /// انتخاب connection
  void selectConnection(String? connectionId) {
    _selectedConnectionId = connectionId;
    _selectedNodeId = null;
    notifyListeners();
  }

  /// شروع اتصال (کشیدن خط)
  void startConnection(String fromNodeId) {
    _isConnecting = true;
    _connectingFromNodeId = fromNodeId;
    notifyListeners();
  }

  /// به‌روزرسانی موقعیت موقتی اتصال
  void updateConnectingPosition(Offset position) {
    _connectingPosition = position;
    notifyListeners();
  }

  /// پایان اتصال (رها کردن)
  void endConnection(String? toNodeId) {
    if (_isConnecting && 
        _connectingFromNodeId != null && 
        toNodeId != null &&
        _connectingFromNodeId != toNodeId) {
      // بررسی که قبلاً این connection وجود نداشته باشد
      final exists = _connections.any(
        (c) => c.sourceNodeId == _connectingFromNodeId && c.targetNodeId == toNodeId,
      );
      if (!exists) {
        final connection = WorkflowConnectionModel(
          id: _uuid.v4(),
          sourceNodeId: _connectingFromNodeId!,
          targetNodeId: toNodeId,
        );
        _connections.add(connection);
      }
    }
    _isConnecting = false;
    _connectingFromNodeId = null;
    _connectingPosition = null;
    notifyListeners();
  }

  /// لغو اتصال
  void cancelConnection() {
    _isConnecting = false;
    _connectingFromNodeId = null;
    _connectingPosition = null;
    notifyListeners();
  }

  /// حذف connection
  void removeConnection(String connectionId) {
    _connections.removeWhere((c) => c.id == connectionId);
    if (_selectedConnectionId == connectionId) {
      _selectedConnectionId = null;
    }
    notifyListeners();
  }

  /// به‌روزرسانی viewport (pan)
  void updateViewport(Offset offset) {
    _viewportOffset = offset;
    notifyListeners();
  }

  /// به‌روزرسانی zoom
  void updateZoom(double zoom) {
    _zoomLevel = zoom.clamp(0.5, 3.0); // TODO: استفاده از WorkflowConstants
    notifyListeners();
  }

  /// بارگذاری metadata trigger ها و action ها
  void loadMetadata({
    required List<WorkflowNodeMetadata> triggers,
    required List<WorkflowNodeMetadata> actions,
  }) {
    _triggers = triggers;
    _actions = actions;
    notifyListeners();
  }

  /// پیدا کردن node با ID
  WorkflowNodeModel? getNodeById(String nodeId) {
    return _nodesMap[nodeId];
  }

  /// پیدا کردن connection های خروجی از یک node
  List<WorkflowConnectionModel> getConnectionsFrom(String nodeId) {
    return _connections.where((c) => c.sourceNodeId == nodeId).toList();
  }

  /// پیدا کردن connection های ورودی به یک node
  List<WorkflowConnectionModel> getConnectionsTo(String nodeId) {
    return _connections.where((c) => c.targetNodeId == nodeId).toList();
  }

  /// Undo
  void undo() {
    if (_history.undo()) {
      notifyListeners();
    }
  }

  /// Redo
  void redo() {
    if (_history.redo()) {
      notifyListeners();
    }
  }

  /// پاک کردن همه چیز
  void clear() {
    _nodes.clear();
    _nodesMap.clear();
    _connections.clear();
    _selectedNodeId = null;
    _selectedConnectionId = null;
    _viewportOffset = Offset.zero;
    _zoomLevel = 1.0;
    _history.clear();
    notifyListeners();
  }
}


