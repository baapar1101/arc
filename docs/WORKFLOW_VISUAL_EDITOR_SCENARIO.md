# سناریو: تبدیل بخش اتوماسیون به Visual Workflow Builder (مشابه n8n)

## 📋 بررسی وضعیت فعلی

### بکند (Backend)
✅ **موجود و آماده:**
- `WorkflowEngine`: موتور اجرای workflow
- `TriggerRegistry` و `ActionRegistry`: سیستم ثبت و مدیریت trigger/action ها
- مدل‌های دیتابیس کامل (`Workflow`, `WorkflowExecution`, `WorkflowLog`)
- API endpoints کامل برای CRUD operations
- ساختار JSON workflow data: `{nodes: [], connections: []}`

### فرانت (Frontend)
⚠️ **نیاز به توسعه دارد:**
- صفحه فعلی (`WorkflowsPage`) فقط یک لیست workflow ها را نمایش می‌دهد
- ویرایشگر فعلی یک TextField ساده برای JSON است (خط 532-543)
- **هیچ visual editor با drag & drop وجود ندارد**

## 🎯 هدف
ایجاد یک Visual Workflow Builder مشابه n8n که امکان:
- ✅ Drag & Drop برای افزودن node ها
- ✅ اتصال node ها با کشیدن خط
- ✅ تنظیم config هر node از طریق dialog
- ✅ پیش‌نمایش workflow به صورت گرافیکی
- ✅ validation و error checking
- ✅ zoom و pan در canvas
- ✅ undo/redo

## 🏗️ معماری پیشنهادی

### 1. ساختار فرانت (Flutter)

#### 1.1 صفحات جدید
```
lib/pages/business/workflows/
├── workflows_list_page.dart          # لیست workflow ها (فایل فعلی)
├── workflow_visual_editor_page.dart  # صفحه جدید: Visual Editor
└── widgets/
    ├── workflow_canvas.dart          # Canvas اصلی برای رسم node ها
    ├── workflow_node.dart            # ویجت هر node
    ├── workflow_connection.dart      # خطوط اتصال بین node ها
    ├── workflow_node_palette.dart    # پالت node های در دسترس
    ├── workflow_node_config_dialog.dart  # Dialog تنظیمات node
    └── workflow_minimap.dart         # نقشه کوچک (اختیاری)
```

#### 1.2 State Management
برای مدیریت state پیچیده workflow editor، پیشنهاد می‌شود از یکی از روش‌های زیر استفاده شود:

**گزینه 1: Riverpod (پیشنهادی)**
```dart
// lib/providers/workflow_editor_provider.dart
final workflowEditorProvider = StateNotifierProvider<WorkflowEditorNotifier, WorkflowEditorState>((ref) {
  return WorkflowEditorNotifier();
});
```

**گزینه 2: BLoC Pattern**
```dart
// lib/blocs/workflow_editor/workflow_editor_bloc.dart
class WorkflowEditorBloc extends Bloc<WorkflowEditorEvent, WorkflowEditorState> {
  // ...
}
```

**گزینه 3: Provider + ChangeNotifier (ساده‌تر)**
```dart
// lib/models/workflow_editor_state.dart
class WorkflowEditorState extends ChangeNotifier {
  List<WorkflowNodeModel> nodes = [];
  List<WorkflowConnectionModel> connections = [];
  Offset viewportOffset = Offset.zero;
  double zoomLevel = 1.0;
  // ...
}
```

### 2. مدل‌های داده

#### 2.1 WorkflowNodeModel
```dart
class WorkflowNodeModel {
  final String id;
  final WorkflowNodeType type; // trigger, action, condition, loop
  final String label;
  final Offset position; // موقعیت در canvas
  final Map<String, dynamic> config; // تنظیمات node
  final String? icon; // آیکون node
  final List<ConnectionPoint> inputs; // نقاط ورودی
  final List<ConnectionPoint> outputs; // نقاط خروجی
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'position': {'x': position.dx, 'y': position.dy},
      'config': config,
    };
  }
  
  factory WorkflowNodeModel.fromJson(Map<String, dynamic> json) {
    // ...
  }
}
```

#### 2.2 WorkflowConnectionModel
```dart
class WorkflowConnectionModel {
  final String id;
  final String sourceNodeId;
  final String sourceOutputId; // شناسه output point
  final String targetNodeId;
  final String targetInputId; // شناسه input point
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': sourceNodeId,
      'source_output': sourceOutputId,
      'target': targetNodeId,
      'target_input': targetInputId,
    };
  }
}
```

#### 2.3 ConnectionPoint
```dart
class ConnectionPoint {
  final String id;
  final String label;
  final ConnectionPointType type; // input, output
  final Offset position; // موقعیت نسبی به node
  final String? dataType; // نوع داده (string, number, object, etc.)
}
```

### 3. کتابخانه‌های پیشنهادی برای Flutter

#### 3.1 گزینه 1: ساخت سفارشی با Flutter Canvas
**مزایا:**
- کنترل کامل روی UI/UX
- بدون dependency اضافی
- سازگار با Material Design

**چالش‌ها:**
- نیاز به کدنویسی بیشتر
- باید drag & drop و connection drawing را خودمان پیاده کنیم

#### 3.2 گزینه 2: استفاده از کتابخانه‌های موجود
بررسی کتابخانه‌های موجود در pub.dev:

1. **graphview** (0.6.1)
   - برای رسم گراف و node ها
   - محدود برای drag & drop پیچیده

2. **flutter_node_view** (نیاز به بررسی)
   - مخصوص node-based editors

3. **diagram_editor** (نیاز به بررسی)
   - برای ویرایشگرهای نمودار

**توصیه: ساخت سفارشی** چون:
- کنترل کامل داریم
- می‌توانیم UI را کاملاً منطبق بر نیازهای پروژه بسازیم
- کتابخانه‌های موجود برای این use case محدود هستند

### 4. معماری Canvas و Rendering

#### 4.1 ساختار کلی Canvas
```dart
class WorkflowCanvas extends StatefulWidget {
  final List<WorkflowNodeModel> nodes;
  final List<WorkflowConnectionModel> connections;
  final Function(WorkflowNodeModel) onNodeAdded;
  final Function(WorkflowConnectionModel) onConnectionAdded;
  // ...
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  late TransformationController _transformationController;
  Offset _panStart = Offset.zero;
  double _zoomLevel = 1.0;
  
  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 3.0,
      child: CustomPaint(
        painter: WorkflowCanvasPainter(
          nodes: widget.nodes,
          connections: widget.connections,
        ),
        child: Stack(
          children: [
            // Background grid
            _buildGrid(),
            
            // Connection lines
            _buildConnections(),
            
            // Node widgets
            ..._buildNodes(),
            
            // Temporary connection line (در حال کشیدن)
            _buildTemporaryConnection(),
          ],
        ),
      ),
    );
  }
}
```

#### 4.2 Drag & Drop برای Node ها
```dart
class WorkflowNode extends StatelessWidget {
  final WorkflowNodeModel node;
  final Function(Offset) onPositionChanged;
  
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: Draggable<WorkflowNodeModel>(
        data: node,
        feedback: _buildNodePreview(),
        childWhenDragging: Container(),
        onDragEnd: (details) {
          onPositionChanged(details.offset);
        },
        child: GestureDetector(
          onPanUpdate: (details) {
            // Update node position
            onPositionChanged(node.position + details.delta);
          },
          child: _buildNodeContent(),
        ),
      ),
    );
  }
}
```

#### 4.3 اتصال Node ها (Connection Drawing)
```dart
class WorkflowConnectionPoint extends StatefulWidget {
  final ConnectionPoint point;
  final WorkflowNodeModel node;
  final Function(ConnectionPoint, Offset) onConnectionStart;
  final Function(ConnectionPoint, Offset) onConnectionEnd;
  
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: point.position.dx,
      top: point.position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          onConnectionStart(point, details.globalPosition);
        },
        onPanUpdate: (details) {
          // Update temporary connection line
        },
        onPanEnd: (details) {
          // Check if dropped on valid connection point
          onConnectionEnd(point, details.globalPosition);
        },
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}
```

#### 4.4 رسم خطوط اتصال (Bezier Curves)
```dart
class WorkflowCanvasPainter extends CustomPainter {
  final List<WorkflowConnectionModel> connections;
  final Map<String, Offset> nodePositions;
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final connection in connections) {
      final startPoint = _getConnectionPoint(connection.sourceNodeId, connection.sourceOutputId);
      final endPoint = _getConnectionPoint(connection.targetNodeId, connection.targetInputId);
      
      // رسم Bezier curve
      final path = Path();
      path.moveTo(startPoint.dx, startPoint.dy);
      
      // Control points برای منحنی
      final cp1 = Offset(startPoint.dx + 50, startPoint.dy);
      final cp2 = Offset(endPoint.dx - 50, endPoint.dy);
      
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, endPoint.dx, endPoint.dy);
      
      final paint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      
      canvas.drawPath(path, paint);
    }
  }
  
  Offset _getConnectionPoint(String nodeId, String pointId) {
    // محاسبه موقعیت واقعی connection point
    // ...
  }
}
```

### 5. پالت Node ها (Node Palette)

```dart
class WorkflowNodePalette extends StatelessWidget {
  final List<TriggerMetadata> triggers;
  final List<ActionMetadata> actions;
  final Function(WorkflowNodeType, String) onNodeSelected;
  
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          _buildSection('Triggers', triggers, WorkflowNodeType.trigger),
          _buildSection('Actions', actions, WorkflowNodeType.action),
          _buildSection('Conditions', conditions, WorkflowNodeType.condition),
        ],
      ),
    );
  }
  
  Widget _buildSection(String title, List<dynamic> items, WorkflowNodeType type) {
    return ExpansionTile(
      title: Text(title),
      children: items.map((item) {
        return ListTile(
          leading: Icon(_getIconForType(type)),
          title: Text(item['name']),
          subtitle: Text(item['description'] ?? ''),
          onTap: () => onNodeSelected(type, item['key']),
        );
      }).toList(),
    );
  }
}
```

### 6. Dialog تنظیمات Node

```dart
class WorkflowNodeConfigDialog extends StatefulWidget {
  final WorkflowNodeModel node;
  final Map<String, dynamic>? schema; // از API دریافت می‌شود
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تنظیمات ${node.label}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: _buildFormFields(schema),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('انصراف'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text('ذخیره'),
        ),
      ],
    );
  }
  
  List<Widget> _buildFormFields(Map<String, dynamic>? schema) {
    // ساخت فیلدهای فرم بر اساس schema
    // استفاده از JSON Schema برای validation
  }
}
```

### 7. Validation و Error Checking

```dart
class WorkflowValidator {
  static List<String> validateWorkflow({
    required List<WorkflowNodeModel> nodes,
    required List<WorkflowConnectionModel> connections,
  }) {
    final errors = <String>[];
    
    // 1. باید حداقل یک trigger node وجود داشته باشد
    if (!nodes.any((n) => n.type == WorkflowNodeType.trigger)) {
      errors.add('Workflow باید حداقل یک trigger داشته باشد');
    }
    
    // 2. هر node باید حداقل یک connection داشته باشد (به جز trigger)
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
      errors.add('Dependency دایره‌ای یافت شد');
    }
    
    // 4. بررسی type matching برای connection points
    for (final conn in connections) {
      if (!_isTypeCompatible(conn, nodes)) {
        errors.add('نوع داده در connection مطابقت ندارد');
      }
    }
    
    return errors;
  }
  
  static bool _hasCircularDependency(
    List<WorkflowNodeModel> nodes,
    List<WorkflowConnectionModel> connections,
  ) {
    // الگوریتم DFS برای تشخیص cycle
    // ...
  }
}
```

### 8. تبدیل به/از JSON

#### 8.1 تبدیل Visual Editor State به Backend Format
```dart
Map<String, dynamic> toBackendFormat() {
  return {
    'nodes': nodes.map((node) => {
      'id': node.id,
      'type': node.type.name,
      'label': node.label,
      'config': node.config,
      // position را در backend ذخیره نکنیم (فقط برای UI)
    }).toList(),
    'connections': connections.map((conn) => {
      'source': conn.sourceNodeId,
      'target': conn.targetNodeId,
    }).toList(),
  };
}
```

#### 8.2 تبدیل Backend Format به Visual Editor State
```dart
static WorkflowEditorState fromBackendFormat(Map<String, dynamic> data) {
  final nodes = (data['nodes'] as List)
      .map((n) => WorkflowNodeModel.fromJson(n))
      .toList();
  
  // محاسبه موقعیت node ها (auto-layout algorithm)
  final positionedNodes = _autoLayoutNodes(nodes);
  
  final connections = (data['connections'] as List)
      .map((c) => WorkflowConnectionModel.fromJson(c))
      .toList();
  
  return WorkflowEditorState(
    nodes: positionedNodes,
    connections: connections,
  );
}

static List<WorkflowNodeModel> _autoLayoutNodes(List<WorkflowNodeModel> nodes) {
  // الگوریتم auto-layout (مثلاً hierarchical layout)
  // ...
}
```

### 9. UX/UI Improvements

#### 9.1 Keyboard Shortcuts
```dart
class WorkflowKeyboardHandler {
  void handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      // حذف node یا connection انتخاب شده
    } else if (event.isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
      // Undo
    } else if (event.isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
      // Redo
    } else if (event.logicalKey == LogicalKeyboardKey.f2) {
      // Rename selected node
    }
  }
}
```

#### 9.2 Mini-map
```dart
class WorkflowMinimap extends StatelessWidget {
  final List<WorkflowNodeModel> nodes;
  final Offset viewportOffset;
  final double zoomLevel;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        border: Border.all(color: Colors.grey),
      ),
      child: CustomPaint(
        painter: MinimapPainter(
          nodes: nodes,
          viewportOffset: viewportOffset,
          zoomLevel: zoomLevel,
        ),
      ),
    );
  }
}
```

#### 9.3 Context Menu
```dart
class WorkflowNodeContextMenu extends StatelessWidget {
  final WorkflowNodeModel node;
  final Function() onDelete;
  final Function() onEdit;
  final Function() onDuplicate;
  
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      itemBuilder: (context) => [
        PopupMenuItem(
          child: Text('ویرایش'),
          onTap: onEdit,
        ),
        PopupMenuItem(
          child: Text('کپی'),
          onTap: onDuplicate,
        ),
        PopupMenuItem(
          child: Text('حذف', style: TextStyle(color: Colors.red)),
          onTap: onDelete,
        ),
      ],
    );
  }
}
```

### 10. Backend Changes (اختیاری)

#### 10.1 Schema Validation API
```python
@router.post(
    "/workflows/{workflow_id}/validate",
    summary="اعتبارسنجی workflow",
)
async def validate_workflow(
    workflow_id: int,
    db: Session = Depends(get_db),
):
    """اعتبارسنجی workflow قبل از فعال کردن"""
    workflow = db.get(Workflow, workflow_id)
    errors = validate_workflow_structure(workflow.workflow_data)
    return {"valid": len(errors) == 0, "errors": errors}
```

#### 10.2 Node Metadata API (بهبود)
```python
@router.get("/workflows/triggers/{trigger_key}/schema")
async def get_trigger_schema(trigger_key: str):
    """دریافت schema برای تنظیمات trigger"""
    registry = TriggerRegistry()
    handler = registry.get_handler(trigger_key)
    if hasattr(handler, 'get_config_schema'):
        return handler.get_config_schema()
    return {}
```

### 11. مراحل پیاده‌سازی (Roadmap)

#### فاز 1: MVP (Minimum Viable Product)
1. ✅ ایجاد `WorkflowVisualEditorPage` با canvas ساده
2. ✅ نمایش node ها در canvas (بدون drag & drop)
3. ✅ رسم خطوط اتصال ساده بین node ها
4. ✅ پالت node ها (فقط نمایش، بدون drag)
5. ✅ Dialog تنظیمات node ساده

**زمان تخمینی: 2-3 هفته**

#### فاز 2: Drag & Drop
1. ✅ Drag & Drop برای افزودن node از پالت
2. ✅ جابجایی node ها در canvas
3. ✅ کشیدن خطوط اتصال بین node ها
4. ✅ حذف node و connection

**زمان تخمینی: 2-3 هفته**

#### فاز 3: پیشرفت‌ها
1. ✅ Zoom و Pan
2. ✅ Validation
3. ✅ Auto-layout
4. ✅ Undo/Redo
5. ✅ Keyboard shortcuts

**زمان تخمینی: 2-3 هفته**

#### فاز 4: Polish
1. ✅ Mini-map
2. ✅ Context menu
3. ✅ Animation
4. ✅ Performance optimization
5. ✅ تست و رفع باگ

**زمان تخمینی: 1-2 هفته**

### 12. چالش‌ها و راه‌حل‌ها

#### چالش 1: Performance
**مشکل:** با تعداد زیاد node ها، rendering کند می‌شود

**راه‌حل:**
- استفاده از `RepaintBoundary` برای هر node
- Virtual scrolling برای node هایی که خارج از viewport هستند
- بهینه‌سازی custom paint operations

#### چالش 2: RTL (Right-to-Left)
**مشکل:** UI باید از راست به چپ باشد

**راه‌حل:**
- استفاده از `Directionality` widget
- تطبیق layout برای RTL

#### چالش 3: Mobile Responsiveness
**مشکل:** Canvas ممکن است در موبایل کار نکند

**راه‌حل:**
- تشخیص platform و نمایش UI متفاوت در موبایل
- یا استفاده از gesture detector مناسب

### 13. نمونه UI/UX (Wireframe)

```
┌─────────────────────────────────────────────────────────┐
│ [☰] Workflow Editor              [Save] [Cancel] [▶]   │
├──────────┬──────────────────────────────────────────────┤
│          │                                              │
│ Triggers │         ┌─────────┐                         │
│ ──────── │         │ Trigger │─────┐                   │
│ • Invoice│         │  Node   │     │                   │
│ • Person │         └─────────┘     │                   │
│          │                         │                   │
│ Actions  │                    ┌─────────┐             │
│ ──────── │                    │  Action │             │
│ • Email  │                    │  Node   │             │
│ • SMS    │                    └─────────┘             │
│ • Notify │                                              │
│          │                    ┌─────────┐             │
│          │                    │ Condition│             │
│          │                    │  Node   │             │
│          │                    └─────────┘             │
│          │                                              │
│          │         [Zoom: 100%] [Grid] [Minimap]      │
└──────────┴──────────────────────────────────────────────┘
```

### 14. منابع و مراجع

1. **n8n UI/UX**: https://n8n.io/ - برای الهام از UX
2. **React Flow**: https://reactflow.dev/ - برای درک معماری (البته Flutter نیست)
3. **Flutter Custom Paint**: https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
4. **Interactive Viewer**: https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html

### 15. سوالات باز برای تصمیم‌گیری

1. ✅ استفاده از State Management: Riverpod یا BLoC یا Provider؟
2. ✅ ساختار پروژه: فایل‌ها کجا قرار بگیرند؟
3. ✅ Auto-layout: استفاده از الگوریتم خاص یا فقط manual positioning؟
4. ✅ Undo/Redo: استفاده از Command Pattern؟
5. ✅ Real-time Collaboration: در آینده نیاز داریم؟

---

## خلاصه

برای تبدیل بخش اتوماسیون به یک Visual Workflow Builder مشابه n8n:

1. **بکند:** آماده است، فقط ممکن است نیاز به endpoint های اضافی باشد
2. **فرانت:** نیاز به ساخت کامل Visual Editor دارد
3. **زمان تخمینی:** 7-11 هفته برای MVP کامل
4. **مهارت‌های مورد نیاز:**
   - Flutter advanced (Custom Paint, Gesture Detection)
   - UI/UX Design
   - Algorithm (graph layout, validation)

**گام بعدی:** شروع با فاز 1 (MVP) و ساخت canvas ساده برای نمایش node ها.


