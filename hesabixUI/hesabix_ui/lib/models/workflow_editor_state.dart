import 'dart:math' as math;

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
  final Set<String> _selectedNodeIds = {}; // Multi-select
  String? _selectedConnectionId;
  bool _isConnecting = false;
  bool _isSelecting = false; // برای selection box
  Offset? _selectionStart;
  Offset? _selectionEnd;
  String? _connectingFromNodeId;
  Offset? _connectingPosition; // موقعیت موقتی هنگام کشیدن خط
  bool _snapToGrid = true; // فعال/غیرفعال بودن snap to grid
  double _gridSize = 20.0; // اندازه grid برای snap
  bool _showGrid = true; // نمایش/عدم نمایش grid

  // Metadata برای node های قابل استفاده
  List<WorkflowNodeMetadata> _triggers = [];
  List<WorkflowNodeMetadata> _actions = [];

  final _uuid = const Uuid();
  final WorkflowHistory _history = WorkflowHistory();
  
  // Clipboard برای copy/paste
  final List<WorkflowNodeModel> _clipboard = [];
  final List<WorkflowConnectionModel> _clipboardConnections = [];

  // Getters
  List<WorkflowNodeModel> get nodes => List.unmodifiable(_nodes);
  List<WorkflowConnectionModel> get connections => List.unmodifiable(_connections);
  Offset get viewportOffset => _viewportOffset;
  double get zoomLevel => _zoomLevel;
  String? get selectedNodeId => _selectedNodeId;
  Set<String> get selectedNodeIds => Set.unmodifiable(_selectedNodeIds);
  bool get hasMultipleSelection => _selectedNodeIds.length > 1;
  String? get selectedConnectionId => _selectedConnectionId;
  bool get isConnecting => _isConnecting;
  bool get isSelecting => _isSelecting;
  Offset? get selectionStart => _selectionStart;
  Offset? get selectionEnd => _selectionEnd;
  String? get connectingFromNodeId => _connectingFromNodeId;
  Offset? get connectingPosition => _connectingPosition;
  bool get snapToGrid => _snapToGrid;
  double get gridSize => _gridSize;
  bool get showGrid => _showGrid;
  List<WorkflowNodeMetadata> get triggers => List.unmodifiable(_triggers);
  List<WorkflowNodeMetadata> get actions => List.unmodifiable(_actions);
  bool get canUndo => _history.canUndo();
  bool get canRedo => _history.canRedo();

  /// بارگذاری workflow از backend format
  void loadWorkflow(Map<String, dynamic> workflowData) {
    try {
      _nodes.clear();
      _connections.clear();
      _nodesMap.clear();

      final nodesRaw = workflowData['nodes'];
      final connectionsRaw = workflowData['connections'];
      
      final nodesJson = nodesRaw is List ? List<dynamic>.from(nodesRaw) : <dynamic>[];
      final connectionsJson = connectionsRaw is List ? List<dynamic>.from(connectionsRaw) : <dynamic>[];

      // تبدیل nodes و بررسی duplicate IDs
      final List<WorkflowNodeModel> loadedNodes = [];
      final Set<String> seenIds = {};
      for (final nodeJson in nodesJson) {
        try {
          if (nodeJson is Map) {
            final nodeMap = <String, dynamic>{};
            for (final entry in nodeJson.entries) {
              nodeMap[entry.key.toString()] = entry.value;
            }
            final node = WorkflowNodeModel.fromJson(nodeMap);
            // اطمینان از اینکه node معتبر است
            if (node.id.isNotEmpty && node.label.isNotEmpty) {
              // بررسی duplicate ID
              if (seenIds.contains(node.id)) {
                debugPrint('هشدار: node با ID تکراری "${node.id}" نادیده گرفته شد');
                // ایجاد ID جدید
                String newId;
                int attempts = 0;
                do {
                  newId = _uuid.v4();
                  attempts++;
                  if (attempts > 10) {
                    debugPrint('خطا: نمی‌توان ID یکتا برای node ایجاد کرد');
                    continue; // skip this node
                  }
                } while (seenIds.contains(newId));
                
                // ایجاد node جدید با ID یکتا
                final newNode = WorkflowNodeModel(
                  id: newId,
                  type: node.type,
                  label: node.label,
                  position: node.position,
                  config: Map<String, dynamic>.from(node.config),
                  key: node.key,
                  icon: node.icon,
                  comment: node.comment,
                );
                loadedNodes.add(newNode);
                _nodesMap[newId] = newNode;
                seenIds.add(newId);
              } else {
                loadedNodes.add(node);
                _nodesMap[node.id] = node;
                seenIds.add(node.id);
              }
            }
          }
        } catch (e, stackTrace) {
          debugPrint('خطا در بارگذاری node: $e');
          debugPrint('StackTrace: $stackTrace');
        }
      }
      _nodes.addAll(loadedNodes);

      // تبدیل connections
      for (final connJson in connectionsJson) {
        try {
          if (connJson is Map) {
            final connMap = <String, dynamic>{};
            for (final entry in connJson.entries) {
              connMap[entry.key.toString()] = entry.value;
            }
            final conn = WorkflowConnectionModel.fromJson(connMap);
            // بررسی اینکه node های مربوط به connection وجود دارند
            if (_nodesMap.containsKey(conn.sourceNodeId) && 
                _nodesMap.containsKey(conn.targetNodeId)) {
              _connections.add(conn);
            }
          }
        } catch (e, stackTrace) {
          debugPrint('خطا در بارگذاری connection: $e');
          debugPrint('StackTrace: $stackTrace');
        }
      }

      // اعمال auto-layout اگر node ها موقعیت ندارند
      _applyAutoLayoutIfNeeded();

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('خطا در loadWorkflow: $e');
      debugPrint('StackTrace: $stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// اعمال auto-layout اگر لازم باشد
  void _applyAutoLayoutIfNeeded() {
    if (_nodes.isEmpty) return;
    
    // بررسی که آیا نودها موقعیت معتبر دارند
    final nodesWithoutPosition = _nodes.where((n) => 
      n.position == Offset.zero || 
      (n.position.dx == 0 && n.position.dy == 0)
    ).toList();

    // اگر حداقل یک نود بدون موقعیت وجود دارد، auto-layout اعمال شود
    if (nodesWithoutPosition.isNotEmpty) {
      final positions = _calculateSimpleLayout();
      for (final node in _nodes) {
        if (positions.containsKey(node.id)) {
          final index = _nodes.indexWhere((n) => n.id == node.id);
          if (index != -1) {
            // فقط نودهایی که موقعیت ندارند را update کن
            if (nodesWithoutPosition.contains(node)) {
              _nodes[index] = node.copyWith(position: positions[node.id]!);
              _nodesMap[node.id] = _nodes[index];
            }
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
    return <String, dynamic>{
      'nodes': _nodes.map((node) => node.toJson()).toList(),
      'connections': _connections.map((conn) => conn.toJson()).toList(),
    };
  }

  /// افزودن node جدید
  void addNode(WorkflowNodeType type, String key, String name) {
    try {
      // بررسی اعتبار ورودی‌ها
      if (key.isEmpty || name.isEmpty) {
        throw ArgumentError('key و name باید غیر خالی باشند');
      }
      
      final position = _calculateNextNodePosition();
      
      // اطمینان از اینکه موقعیت معتبر است
      final validPosition = _isValidPosition(position) 
          ? position 
          : const Offset(200, 200);
      
      final config = <String, dynamic>{};
      // مقداردهی اولیه config برای loop
      if (type == WorkflowNodeType.loop) {
        if (key == 'loop.for_each') {
          config['loop_type'] = 'for_each';
          config['items_source'] = '';
          config['item_variable'] = 'item';
          config['index_variable'] = 'index';
          config['max_iterations'] = 1000;
        } else if (key == 'loop.for') {
          config['loop_type'] = 'for_range';
          config['start'] = 0;
          config['end'] = 10;
          config['step'] = 1;
          config['index_variable'] = 'index';
          config['max_iterations'] = 1000;
        } else if (key == 'loop.while') {
          config['loop_type'] = 'while';
          config['condition'] = {
            'left_value': '',
            'operator': '==',
            'right_value': '',
          };
          config['max_iterations'] = 1000;
        }
      }
      
      // ایجاد ID جدید و بررسی duplicate
      String nodeId;
      int attempts = 0;
      do {
        nodeId = _uuid.v4();
        attempts++;
        if (attempts > 10) {
          throw StateError('نمی‌توان ID یکتا برای node ایجاد کرد');
        }
      } while (_nodesMap.containsKey(nodeId));
      
      final node = WorkflowNodeModel(
        id: nodeId,
        type: type,
        label: name,
        position: validPosition,
        key: key,
        config: config,
      );
      
      _nodes.add(node);
      _nodesMap[node.id] = node;
      
      // اضافه کردن به history
      try {
        final command = AddNodeCommand(this, node);
        command.execute();
        _history.addCommand(command);
      } catch (e) {
        debugPrint('خطا در اضافه کردن به history: $e');
        // ادامه دادن حتی اگر history خطا داشته باشد
      }
      
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('خطا در addNode: $e');
      // در صورت خطا، listeners را اطلاع بده تا UI به‌روزرسانی شود
      notifyListeners();
      rethrow;
    }
  }

  /// افزودن node با موقعیت مشخص
  void addNodeWithPosition(WorkflowNodeModel node) {
    // بررسی duplicate ID
    if (_nodesMap.containsKey(node.id)) {
      debugPrint('هشدار: node با ID تکراری "${node.id}" نادیده گرفته شد');
      // ایجاد ID جدید برای node
      String newId;
      int attempts = 0;
      do {
        newId = _uuid.v4();
        attempts++;
        if (attempts > 10) {
          throw StateError('نمی‌توان ID یکتا برای node ایجاد کرد');
        }
      } while (_nodesMap.containsKey(newId));
      
      // ایجاد node جدید با ID یکتا
      final newNode = WorkflowNodeModel(
        id: newId,
        type: node.type,
        label: node.label,
        position: node.position,
        config: Map<String, dynamic>.from(node.config),
        key: node.key,
        icon: node.icon,
        comment: node.comment,
      );
      
      _nodes.add(newNode);
      _nodesMap[newId] = newNode;
    } else {
      _nodes.add(node);
      _nodesMap[node.id] = node;
    }
    notifyListeners();
  }

  /// محاسبه موقعیت بعدی برای node جدید
  Offset _calculateNextNodePosition() {
    try {
      if (_nodes.isEmpty) {
        final position = const Offset(200, 200);
        return _snapToGrid ? _snapToGridPosition(position) : position;
      }
      
      // استفاده از الگوریتم Grid-Based Placement
      return _findEmptyGridPosition();
    } catch (e) {
      debugPrint('خطا در _calculateNextNodePosition: $e');
      // در صورت خطا، موقعیت پیش‌فرض را برگردان
      return const Offset(200, 200);
    }
  }

  /// پیدا کردن اولین موقعیت خالی در grid
  Offset _findEmptyGridPosition() {
    // تعریف اندازه سلول grid (باید بزرگتر از اندازه node باشد)
    const double cellWidth = 250.0;  // عرض node = 180 + فاصله 70
    const double cellHeight = 150.0; // ارتفاع node = 100 + فاصله 50
    const double startX = 100.0;
    const double startY = 100.0;
    const int maxColumns = 8; // حداکثر 8 ستون
    const int maxRows = 50;   // حداکثر 50 سطر
    
    // جمع‌آوری موقعیت‌های اشغال شده با margin بیشتر
    final occupiedRegions = <Rect>[];
    for (final node in _nodes) {
      if (_isValidPosition(node.position)) {
        // ایجاد یک منطقه بزرگتر برای هر node
        occupiedRegions.add(Rect.fromLTWH(
          node.position.dx - 40,
          node.position.dy - 30,
          180 + 80, // node width + margin
          100 + 60, // node height + margin
        ));
      }
    }
    
    // پیدا کردن اولین سلول خالی (از چپ به راست، از بالا به پایین)
    for (int row = 0; row < maxRows; row++) {
      for (int col = 0; col < maxColumns; col++) {
        final x = startX + (col * cellWidth);
        final y = startY + (row * cellHeight);
        final position = Offset(x, y);
        
        // بررسی اینکه این موقعیت با هیچ node دیگری تداخل ندارد
        bool hasOverlap = false;
        final testRect = Rect.fromLTWH(x, y, 180, 100);
        
        for (final occupiedRect in occupiedRegions) {
          if (testRect.overlaps(occupiedRect)) {
            hasOverlap = true;
            break;
          }
        }
        
        if (!hasOverlap) {
          return _snapToGrid ? _snapToGridPosition(position) : position;
        }
      }
    }
    
    // اگر جای خالی پیدا نشد، موقعیت در ستون بعدی
    final lastRow = (_nodes.length / maxColumns).floor();
    final lastCol = _nodes.length % maxColumns;
    return Offset(
      startX + (lastCol * cellWidth),
      startY + (lastRow * cellHeight),
    );
  }

  /// بررسی تداخل با node های موجود
  bool _hasCollision(Offset newPosition, {String? excludeNodeId}) {
    const double nodeWidth = 180.0;
    const double nodeHeight = 100.0;
    const double minHorizontalGap = 50.0; // حداقل فاصله افقی
    const double minVerticalGap = 30.0;   // حداقل فاصله عمودی
    
    final newRect = Rect.fromLTWH(
      newPosition.dx - minHorizontalGap / 2,
      newPosition.dy - minVerticalGap / 2,
      nodeWidth + minHorizontalGap,
      nodeHeight + minVerticalGap,
    );
    
    for (final node in _nodes) {
      // اگر این node باید نادیده گرفته شود (مثلاً برای جابجایی)
      if (excludeNodeId != null && node.id == excludeNodeId) {
        continue;
      }
      
      final nodeRect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        nodeWidth,
        nodeHeight,
      );
      
      if (newRect.overlaps(nodeRect)) {
        return true;
      }
    }
    
    return false;
  }

  /// پیدا کردن نزدیک‌ترین موقعیت خالی به یک موقعیت مشخص
  Offset findNearestEmptyPosition(Offset targetPosition, {String? excludeNodeId}) {
    if (!_hasCollision(targetPosition, excludeNodeId: excludeNodeId)) {
      return targetPosition;
    }
    
    // جستجوی دایره‌ای با شعاع فزاینده
    const double step = 20.0;
    const int maxRadius = 500;
    
    for (double radius = step; radius < maxRadius; radius += step) {
      // بررسی 8 جهت اصلی
      final directions = [
        Offset(radius, 0),      // راست
        Offset(-radius, 0),     // چپ
        Offset(0, radius),      // پایین
        Offset(0, -radius),     // بالا
        Offset(radius, radius), // راست-پایین
        Offset(-radius, radius),// چپ-پایین
        Offset(radius, -radius),// راست-بالا
        Offset(-radius, -radius),// چپ-بالا
      ];
      
      for (final direction in directions) {
        final newPosition = targetPosition + direction;
        if (!_hasCollision(newPosition, excludeNodeId: excludeNodeId) && 
            _isValidPosition(newPosition)) {
          return newPosition;
        }
      }
    }
    
    // اگر جایی پیدا نشد، از الگوریتم grid استفاده کن
    return _findEmptyGridPosition();
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

  /// به‌روزرسانی موقعیت node با snap to grid
  void updateNodePosition(String nodeId, Offset newPosition, {bool trackHistory = false}) {
    try {
      // بررسی اعتبار موقعیت جدید
      if (!_isValidPosition(newPosition)) {
        return;
      }
      
      final index = _nodes.indexWhere((n) => n.id == nodeId);
      if (index != -1) {
        // اعمال snap to grid
        Offset finalPosition = _snapToGrid ? _snapToGridPosition(newPosition) : newPosition;
        
        // بررسی مجدد اعتبار موقعیت پس از snap
        if (!_isValidPosition(finalPosition)) {
          return;
        }
        
        final oldPosition = _nodes[index].position;
        if (trackHistory && oldPosition != finalPosition) {
          final command = MoveNodeCommand(this, nodeId, oldPosition, finalPosition);
          command.execute();
          _history.addCommand(command);
        } else {
          _nodes[index] = _nodes[index].copyWith(position: finalPosition);
          _nodesMap[nodeId] = _nodes[index]; // به‌روزرسانی map
        }
        notifyListeners();
      }
    } catch (e, stackTrace) {
      debugPrint('خطا در updateNodePosition: $e');
    }
  }

  /// به‌روزرسانی موقعیت node بدون snap (برای drag سریع‌تر)
  void updateNodePositionWithoutSnap(String nodeId, Offset newPosition) {
    try {
      if (!_isValidPosition(newPosition)) {
        return;
      }
      
      final index = _nodes.indexWhere((n) => n.id == nodeId);
      if (index != -1) {
        _nodes[index] = _nodes[index].copyWith(position: newPosition);
        _nodesMap[nodeId] = _nodes[index];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطا در updateNodePositionWithoutSnap: $e');
    }
  }

  /// اعمال snap to grid روی یک node (برای استفاده در پایان drag)
  void snapNodeToGrid(String nodeId) {
    if (!_snapToGrid) return;
    
    try {
      final node = getNodeById(nodeId);
      if (node != null) {
        final snappedPosition = _snapToGridPosition(node.position);
        if (snappedPosition != node.position) {
          final index = _nodes.indexWhere((n) => n.id == nodeId);
          if (index != -1) {
            _nodes[index] = _nodes[index].copyWith(position: snappedPosition);
            _nodesMap[nodeId] = _nodes[index];
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('خطا در snapNodeToGrid: $e');
    }
  }

  /// بررسی اعتبار یک موقعیت
  bool _isValidPosition(Offset position) {
    return position.dx.isFinite && 
           position.dy.isFinite &&
           !position.dx.isNaN && 
           !position.dy.isNaN;
  }

  /// Snap کردن موقعیت به grid
  Offset _snapToGridPosition(Offset position) {
    try {
      // بررسی اعتبار موقعیت ورودی
      if (!_isValidPosition(position)) {
        return const Offset(200, 200);
      }
      
      if (!_snapToGrid || _gridSize <= 0 || !_gridSize.isFinite || _gridSize.isNaN) {
        return position;
      }
      
      final snappedX = (position.dx / _gridSize).round() * _gridSize;
      final snappedY = (position.dy / _gridSize).round() * _gridSize;
      
      // بررسی اعتبار موقعیت snapped
      final result = Offset(snappedX, snappedY);
      if (!_isValidPosition(result)) {
        return position; // در صورت خطا، موقعیت اصلی را برگردان
      }
      
      return result;
    } catch (e) {
      debugPrint('خطا در _snapToGridPosition: $e');
      // در صورت خطا، موقعیت اصلی را برگردان (اگر معتبر است)
      return _isValidPosition(position) ? position : const Offset(200, 200);
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

  /// تنظیم نمایش grid
  void setShowGrid(bool show) {
    _showGrid = show;
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
      // ایجاد یک Map جدید با کپی کردن config
      final newConfig = <String, dynamic>{};
      newConfig.addAll(config);
      _nodes[index] = _nodes[index].copyWith(config: newConfig);
      _nodesMap[nodeId] = _nodes[index]; // به‌روزرسانی map
      notifyListeners();
    }
  }

  /// انتخاب node
  void selectNode(String? nodeId, {bool addToSelection = false, bool toggle = false}) {
    if (nodeId == null) {
      // لغو همه انتخاب‌ها
      _selectedNodeId = null;
      _selectedNodeIds.clear();
      _selectedConnectionId = null;
    } else {
      if (toggle) {
        // Toggle: اگر انتخاب شده، حذف کن، وگرنه اضافه کن
        if (_selectedNodeIds.contains(nodeId)) {
          _selectedNodeIds.remove(nodeId);
          if (_selectedNodeId == nodeId) {
            _selectedNodeId = _selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null;
          }
        } else {
          _selectedNodeIds.add(nodeId);
          _selectedNodeId = nodeId;
        }
      } else if (addToSelection) {
        // اضافه کردن به انتخاب فعلی
        _selectedNodeIds.add(nodeId);
        _selectedNodeId = nodeId;
      } else {
        // انتخاب تکی (پاک کردن انتخاب‌های قبلی)
        _selectedNodeIds.clear();
        _selectedNodeIds.add(nodeId);
        _selectedNodeId = nodeId;
      }
      _selectedConnectionId = null;
    }
    notifyListeners();
  }

  /// انتخاب چند node
  void selectMultipleNodes(List<String> nodeIds, {bool addToSelection = false}) {
    if (!addToSelection) {
      _selectedNodeIds.clear();
    }
    _selectedNodeIds.addAll(nodeIds);
    _selectedNodeId = nodeIds.isNotEmpty ? nodeIds.last : null;
    _selectedConnectionId = null;
    notifyListeners();
  }

  /// شروع selection box
  void startSelection(Offset position) {
    _isSelecting = true;
    _selectionStart = position;
    _selectionEnd = position;
    notifyListeners();
  }

  /// به‌روزرسانی selection box
  void updateSelection(Offset position) {
    if (_isSelecting) {
      _selectionEnd = position;
      // پیدا کردن نودهای داخل selection box
      _updateNodesInSelectionBox();
      notifyListeners();
    }
  }

  /// پایان selection box
  void endSelection() {
    _isSelecting = false;
    _selectionStart = null;
    _selectionEnd = null;
    notifyListeners();
  }

  /// به‌روزرسانی نودهای داخل selection box
  void _updateNodesInSelectionBox() {
    if (_selectionStart == null || _selectionEnd == null) return;

    final left = math.min(_selectionStart!.dx, _selectionEnd!.dx);
    final right = math.max(_selectionStart!.dx, _selectionEnd!.dx);
    final top = math.min(_selectionStart!.dy, _selectionEnd!.dy);
    final bottom = math.max(_selectionStart!.dy, _selectionEnd!.dy);
    final selectionRect = Rect.fromLTRB(left, top, right, bottom);

    _selectedNodeIds.clear();
    for (final node in _nodes) {
      const double nodeWidth = 180.0;
      const double nodeHeight = 100.0;
      final nodeRect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        nodeWidth,
        nodeHeight,
      );
      
      if (selectionRect.overlaps(nodeRect)) {
        _selectedNodeIds.add(node.id);
      }
    }
    
    _selectedNodeId = _selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null;
  }

  /// حذف نودهای انتخاب شده
  void deleteSelectedNodes() {
    if (_selectedNodeIds.isEmpty) return;
    
    for (final nodeId in _selectedNodeIds.toList()) {
      removeNode(nodeId);
    }
    
    _selectedNodeIds.clear();
    _selectedNodeId = null;
    notifyListeners();
  }

  /// جابجایی نودهای انتخاب شده
  void moveSelectedNodes(Offset delta) {
    if (_selectedNodeIds.isEmpty) return;
    
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        final newPosition = node.position + delta;
        if (_isValidPosition(newPosition)) {
          updateNodePosition(nodeId, newPosition);
        }
      }
    }
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
  /// [sourceOutputId] برای نود شرط: "true" یا "false" برای شاخه‌بندی
  void endConnection(String? toNodeId, {String? sourceOutputId}) {
    if (_isConnecting && 
        _connectingFromNodeId != null && 
        toNodeId != null &&
        _connectingFromNodeId != toNodeId) {
      // برای نود شرط: بررسی duplicate با توجه به sourceOutputId
      final exists = _connections.any(
        (c) =>
            c.sourceNodeId == _connectingFromNodeId &&
            c.targetNodeId == toNodeId &&
            (c.sourceOutputId ?? '') == (sourceOutputId ?? ''),
      );
      if (!exists) {
        final connection = WorkflowConnectionModel(
          id: _uuid.v4(),
          sourceNodeId: _connectingFromNodeId!,
          targetNodeId: toNodeId,
          sourceOutputId: sourceOutputId,
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
    _selectedNodeIds.clear();
    _selectedConnectionId = null;
    _viewportOffset = Offset.zero;
    _zoomLevel = 1.0;
    _history.clear();
    _clipboard.clear();
    _clipboardConnections.clear();
    notifyListeners();
  }

  /// کپی کردن نودهای انتخاب شده
  void copySelectedNodes() {
    if (_selectedNodeIds.isEmpty) return;
    
    _clipboard.clear();
    _clipboardConnections.clear();
    
    // کپی نودها
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        _clipboard.add(node);
      }
    }
    
    // کپی connectionهای بین نودهای انتخاب شده
    for (final conn in _connections) {
      if (_selectedNodeIds.contains(conn.sourceNodeId) && 
          _selectedNodeIds.contains(conn.targetNodeId)) {
        _clipboardConnections.add(conn);
      }
    }
    
    debugPrint('کپی شد: ${_clipboard.length} نود و ${_clipboardConnections.length} اتصال');
  }

  /// برش نودهای انتخاب شده
  void cutSelectedNodes() {
    if (_selectedNodeIds.isEmpty) return;
    
    copySelectedNodes();
    deleteSelectedNodes();
  }

  /// چسباندن نودهای کپی شده
  void pasteNodes({Offset? offset}) {
    if (_clipboard.isEmpty) return;
    
    final pasteOffset = offset ?? const Offset(50, 50);
    final nodeIdMap = <String, String>{}; // mapping از ID قدیم به جدید
    final newNodes = <WorkflowNodeModel>[];
    
    // ایجاد نودهای جدید
    for (final node in _clipboard) {
      final newId = _uuid.v4();
      nodeIdMap[node.id] = newId;
      
      // محاسبه موقعیت جدید
      final newPosition = node.position + pasteOffset;
      final finalPosition = findNearestEmptyPosition(newPosition);
      
      final newNode = WorkflowNodeModel(
        id: newId,
        type: node.type,
        label: node.label,
        position: finalPosition,
        config: Map<String, dynamic>.from(node.config),
        key: node.key,
        icon: node.icon,
      );
      
      newNodes.add(newNode);
      _nodes.add(newNode);
      _nodesMap[newId] = newNode;
    }
    
    // ایجاد connectionهای جدید
    for (final conn in _clipboardConnections) {
      final newSourceId = nodeIdMap[conn.sourceNodeId];
      final newTargetId = nodeIdMap[conn.targetNodeId];
      
      if (newSourceId != null && newTargetId != null) {
        final newConn = WorkflowConnectionModel(
          id: _uuid.v4(),
          sourceNodeId: newSourceId,
          targetNodeId: newTargetId,
        );
        _connections.add(newConn);
      }
    }
    
    // انتخاب نودهای جدید
    _selectedNodeIds.clear();
    _selectedNodeIds.addAll(newNodes.map((n) => n.id));
    _selectedNodeId = newNodes.isNotEmpty ? newNodes.first.id : null;
    
    debugPrint('Paste شد: ${newNodes.length} نود');
    notifyListeners();
  }

  /// بررسی اینکه clipboard خالی است یا نه
  bool get hasClipboardContent => _clipboard.isNotEmpty;

  /// اعتبارسنجی یک نود
  List<String> validateNode(String nodeId) {
    final errors = <String>[];
    final node = getNodeById(nodeId);
    
    if (node == null) {
      return ['نود یافت نشد'];
    }
    
    // بررسی trigger ها
    if (node.type == WorkflowNodeType.trigger) {
      // بررسی اینکه trigger حداقل یک connection خروجی دارد
      final outgoingConnections = getConnectionsFrom(nodeId);
      if (outgoingConnections.isEmpty) {
        errors.add('Trigger باید حداقل یک اتصال خروجی داشته باشد');
      }
    }
    
    // بررسی action ها
    if (node.type == WorkflowNodeType.action) {
      // بررسی اینکه action حداقل یک connection ورودی دارد
      final incomingConnections = getConnectionsTo(nodeId);
      if (incomingConnections.isEmpty) {
        errors.add('Action باید حداقل یک اتصال ورودی داشته باشد');
      }
    }
    
    // بررسی condition ها
    if (node.type == WorkflowNodeType.condition) {
      final incomingConnections = getConnectionsTo(nodeId);
      if (incomingConnections.isEmpty) {
        errors.add('Condition باید حداقل یک اتصال ورودی داشته باشد');
      }
      
      final outgoingConnections = getConnectionsFrom(nodeId);
      if (outgoingConnections.isEmpty) {
        errors.add('Condition باید حداقل یک اتصال خروجی داشته باشد');
      }
    }
    
    // بررسی loop ها
    if (node.type == WorkflowNodeType.loop) {
      final incomingConnections = getConnectionsTo(nodeId);
      if (incomingConnections.isEmpty) {
        errors.add('Loop باید حداقل یک اتصال ورودی داشته باشد');
      }
    }
    
    return errors;
  }

  /// دریافت همه نودهای دارای خطا
  Map<String, List<String>> getAllValidationErrors() {
    final errors = <String, List<String>>{};
    
    for (final node in _nodes) {
      final nodeErrors = validateNode(node.id);
      if (nodeErrors.isNotEmpty) {
        errors[node.id] = nodeErrors;
      }
    }
    
    return errors;
  }

  /// بررسی اینکه نود خطا دارد یا نه
  bool hasNodeError(String nodeId) {
    return validateNode(nodeId).isNotEmpty;
  }

  /// Alignment Tools

  /// تراز کردن نودهای انتخاب شده به چپ
  void alignNodesLeft() {
    if (_selectedNodeIds.length < 2) return;
    
    double minX = double.infinity;
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null && node.position.dx < minX) {
        minX = node.position.dx;
      }
    }
    
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        updateNodePosition(nodeId, Offset(minX, node.position.dy));
      }
    }
  }

  /// تراز کردن نودهای انتخاب شده به راست
  void alignNodesRight() {
    if (_selectedNodeIds.length < 2) return;
    
    double maxX = double.negativeInfinity;
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null && node.position.dx > maxX) {
        maxX = node.position.dx;
      }
    }
    
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        updateNodePosition(nodeId, Offset(maxX, node.position.dy));
      }
    }
  }

  /// تراز کردن نودهای انتخاب شده به بالا
  void alignNodesTop() {
    if (_selectedNodeIds.length < 2) return;
    
    double minY = double.infinity;
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null && node.position.dy < minY) {
        minY = node.position.dy;
      }
    }
    
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        updateNodePosition(nodeId, Offset(node.position.dx, minY));
      }
    }
  }

  /// تراز کردن نودهای انتخاب شده به پایین
  void alignNodesBottom() {
    if (_selectedNodeIds.length < 2) return;
    
    double maxY = double.negativeInfinity;
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null && node.position.dy > maxY) {
        maxY = node.position.dy;
      }
    }
    
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        updateNodePosition(nodeId, Offset(node.position.dx, maxY));
      }
    }
  }

  /// توزیع یکنواخت افقی نودهای انتخاب شده
  void distributeNodesHorizontally() {
    if (_selectedNodeIds.length < 3) return;
    
    final selectedNodes = _selectedNodeIds
        .map((id) => getNodeById(id))
        .whereType<WorkflowNodeModel>()
        .toList()
      ..sort((a, b) => a.position.dx.compareTo(b.position.dx));
    
    if (selectedNodes.length < 3) return;
    
    final minX = selectedNodes.first.position.dx;
    final maxX = selectedNodes.last.position.dx;
    final spacing = (maxX - minX) / (selectedNodes.length - 1);
    
    for (int i = 1; i < selectedNodes.length - 1; i++) {
      final newX = minX + (spacing * i);
      updateNodePosition(
        selectedNodes[i].id,
        Offset(newX, selectedNodes[i].position.dy),
      );
    }
  }

  /// توزیع یکنواخت عمودی نودهای انتخاب شده
  void distributeNodesVertically() {
    if (_selectedNodeIds.length < 3) return;
    
    final selectedNodes = _selectedNodeIds
        .map((id) => getNodeById(id))
        .whereType<WorkflowNodeModel>()
        .toList()
      ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
    
    if (selectedNodes.length < 3) return;
    
    final minY = selectedNodes.first.position.dy;
    final maxY = selectedNodes.last.position.dy;
    final spacing = (maxY - minY) / (selectedNodes.length - 1);
    
    for (int i = 1; i < selectedNodes.length - 1; i++) {
      final newY = minY + (spacing * i);
      updateNodePosition(
        selectedNodes[i].id,
        Offset(selectedNodes[i].position.dx, newY),
      );
    }
  }

  /// تراز کردن نودهای انتخاب شده به grid
  void alignSelectedNodesToGrid() {
    for (final nodeId in _selectedNodeIds) {
      final node = getNodeById(nodeId);
      if (node != null) {
        final snappedPosition = _snapToGridPosition(node.position);
        updateNodePosition(nodeId, snappedPosition);
      }
    }
  }
}


