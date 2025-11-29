import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../services/workflow_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../utils/workflow_validator.dart';
import '../../utils/workflow_auto_layout.dart';
import '../../utils/workflow_constants.dart';
import '../../widgets/workflow/workflow_canvas.dart';
import '../../widgets/workflow/workflow_minimap.dart';
import '../../widgets/workflow/workflow_node_config_dialog.dart';
import '../../widgets/workflow/workflow_node_context_menu.dart';
import '../../widgets/workflow/workflow_node_palette.dart';
import '../../widgets/workflow/workflow_toolbar_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class WorkflowVisualEditorPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final Map<String, dynamic>? workflow;

  const WorkflowVisualEditorPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.workflow,
  });

  @override
  State<WorkflowVisualEditorPage> createState() => _WorkflowVisualEditorPageState();
}

class _WorkflowVisualEditorPageState extends State<WorkflowVisualEditorPage> {
  final WorkflowService _workflowService = WorkflowService();
  final WorkflowEditorState _editorState = WorkflowEditorState();
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _workflow;
  List<WorkflowNodeMetadata> _triggers = const [];
  List<WorkflowNodeMetadata> _actions = const [];
  final FocusNode _focusNode = FocusNode();
  final _uuid = const Uuid();
  WorkflowAutoLayoutType _layoutType = WorkflowAutoLayoutType.hierarchical;

  @override
  void initState() {
    super.initState();
    _workflow = widget.workflow;
    _loadData();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _editorState.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _workflowService.listTriggers(),
        _workflowService.listActions(),
      ]);

      final triggers = (results[0] as List<Map<String, dynamic>>)
          .map((item) => WorkflowNodeMetadata(
                key: item['key'] as String,
                name: item['name'] as String? ?? item['key'] as String,
                description: item['description'] as String?,
                type: WorkflowNodeType.trigger,
                configSchema: item['config_schema'] as Map<String, dynamic>?,
              ))
          .toList();

      final actions = (results[1] as List<Map<String, dynamic>>)
          .map((item) => WorkflowNodeMetadata(
                key: item['key'] as String,
                name: item['name'] as String? ?? item['key'] as String,
                description: item['description'] as String?,
                type: WorkflowNodeType.action,
                configSchema: item['config_schema'] as Map<String, dynamic>?,
              ))
          .toList();

      _triggers = triggers;
      _actions = actions;
      _editorState.loadMetadata(triggers: triggers, actions: actions);

      if (_workflow != null) {
        final workflowData = _workflow?['workflow_data'];
        if (workflowData is String) {
          final decoded = jsonDecode(workflowData) as Map<String, dynamic>;
          _editorState.loadWorkflow(decoded);
        } else if (workflowData is Map<String, dynamic>) {
          _editorState.loadWorkflow(workflowData);
        } else {
          _editorState.loadWorkflow({'nodes': [], 'connections': []});
        }
      } else {
        _editorState.clear();
      }
    } catch (e, stackTrace) {
      debugPrint('خطا در بارگذاری داده‌های workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).workflowErrorLoading)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canAccess = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.canReadSection('settings');

    if (!canAccess) {
      return AccessDeniedPage(
        message: t.workflowNoAccessEditor,
      );
    }

    final title = widget.workflow == null
        ? t.newWorkflow
        : t.editWorkflow;

    // تشخیص اندازه صفحه برای responsive design
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final isTablet = screenSize.width < 1024;
    final drawerWidth = isMobile ? screenSize.width * 0.85 : (isTablet ? 350.0 : 300.0);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // وقتی route تغییر می‌کند، صفحه را ببند
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            // در موبایل فقط آیکون ذخیره نمایش داده شود
            isMobile
                ? IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _loading ? null : _saveWorkflow,
                    tooltip: t.workflowSave,
                  )
                : TextButton.icon(
                    onPressed: _loading ? null : _saveWorkflow,
                    icon: const Icon(Icons.save),
                    label: Text(t.workflowSave),
                  ),
          ],
        ),
      drawer: Drawer(
        width: drawerWidth,
        child: WorkflowNodePaletteContent(
          triggers: _triggers,
          actions: _actions,
          onNodeSelected: (type, key, name) {
            try {
              _editorState.addNode(type, key, name);
              Navigator.of(context).maybePop();
            } catch (e, stackTrace) {
              debugPrint('خطا در افزودن نود: $e');
              debugPrint('StackTrace: $stackTrace');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('خطا در افزودن نود: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: LoadingIndicator())
          : KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: Stack(
                children: [
                  Column(
                    children: [
                      WorkflowToolbarWidget(
                        state: _editorState,
                        layoutType: _layoutType,
                        onClear: () {
                          _editorState.clear();
                        },
                        onAutoLayout: () {
                          _applyAutoLayout();
                        },
                        onUndo: () {
                          _editorState.undo();
                        },
                        onRedo: () {
                          _editorState.redo();
                        },
                        onLayoutTypeChanged: (type) {
                          setState(() {
                            _layoutType = type;
                          });
                          _applyAutoLayout();
                        },
                      ),
                      Expanded(
                        child: WorkflowCanvas(
                          state: _editorState,
                          onNodeTap: (node) async {
                            final result = await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => WorkflowNodeConfigDialog(
                                node: node,
                                editorState: _editorState,
                              ),
                            );
                            if (result != null) {
                              _editorState.updateNodeConfig(node.id, result);
                            }
                          },
                          onNodeLongPress: (node, position) {
                            WorkflowNodeContextMenu.show(
                              context,
                              position,
                              node: node,
                              onEdit: () async {
                                Navigator.pop(context); // بستن context menu
                                await Future.delayed(const Duration(milliseconds: 100));
                                final result = await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (_) => WorkflowNodeConfigDialog(
                                    node: node,
                                    editorState: _editorState,
                                  ),
                                );
                                if (result != null && mounted) {
                                  _editorState.updateNodeConfig(node.id, result);
                                }
                              },
                              onDuplicate: () {
                                Navigator.pop(context);
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  if (mounted) _duplicateNode(node);
                                });
                              },
                              onDelete: () {
                                Navigator.pop(context);
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  if (mounted) _deleteNode(node);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  // Mini-map در گوشه پایین راست (فقط در desktop و tablet)
                  if (!isMobile)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: WorkflowMinimap(
                        state: _editorState,
                        canvasSize: const Size(2000, 2000),
                        viewportOffset: _editorState.viewportOffset,
                        zoomLevel: _editorState.zoomLevel,
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }

  void _applyAutoLayout({WorkflowAutoLayoutType? type}) {
    final layoutType = type ?? _layoutType;
    final positions = WorkflowAutoLayout.applyLayout(
      type: layoutType,
      nodes: _editorState.nodes,
      connections: _editorState.connections,
    );

    for (final entry in positions.entries) {
      _editorState.updateNodePosition(entry.key, entry.value);
    }

    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          layoutType == WorkflowAutoLayoutType.hierarchical
              ? t.workflowHierarchicalLayoutApplied
              : t.workflowForceDirectedLayoutApplied,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveWorkflow() async {
    if (_saving) return;

    // Validation
    final errors = WorkflowValidator.validateWorkflow(
      nodes: _editorState.nodes,
      connections: _editorState.connections,
      context: context,
    );

    if (errors.isNotEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).workflowValidationError),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: errors.map((error) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error)),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).workflowClose),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'name': _workflow?['name'] ?? AppLocalizations.of(context).newWorkflow,
        'description': _workflow?['description'],
        'status': _workflow?['status'] ?? AppLocalizations.of(context).workflowDraft,
        'workflow_data': _editorState.toBackendFormat(),
      };

      if (_workflow == null) {
        await _workflowService.createWorkflow(
          businessId: widget.businessId,
          payload: payload,
        );
      } else {
        await _workflowService.updateWorkflow(
          businessId: widget.businessId,
          workflowId: _workflow!['id'] as int,
          payload: payload,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowSaved)),
      );
      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      debugPrint('خطا در ذخیره‌سازی workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowErrorSaving)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlPressed = event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight ||
          HardwareKeyboard.instance.isControlPressed;
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

      // Delete key
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _deleteSelectedNode();
        return;
      }

      // Ctrl+Z (Undo)
      if (isCtrlPressed && 
          event.logicalKey == LogicalKeyboardKey.keyZ && 
          !isShiftPressed) {
        if (_editorState.canUndo) {
          _editorState.undo();
        }
        return;
      }

      // Ctrl+Y یا Ctrl+Shift+Z (Redo)
      if (isCtrlPressed && 
          (event.logicalKey == LogicalKeyboardKey.keyY ||
           (event.logicalKey == LogicalKeyboardKey.keyZ && isShiftPressed))) {
        if (_editorState.canRedo) {
          _editorState.redo();
        }
        return;
      }

      // Ctrl+S (Save)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveWorkflow();
        return;
      }

      // Escape (لغو اتصال یا انتخاب)
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_editorState.isConnecting) {
          _editorState.cancelConnection();
        } else {
          _editorState.selectNode(null);
          _editorState.selectConnection(null);
        }
        return;
      }

      // Arrow Keys - حرکت نود انتخاب شده
      final selectedNodeId = _editorState.selectedNodeId;
      if (selectedNodeId != null) {
        const step = 10.0;
        Offset? delta;
        
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          delta = Offset(0, -step);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          delta = Offset(0, step);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          delta = Offset(-step, 0);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          delta = Offset(step, 0);
        }

        if (delta != null) {
          final selectedNode = _editorState.getNodeById(selectedNodeId);
          if (selectedNode != null) {
            final newPosition = selectedNode.position + delta;
            _editorState.updateNodePosition(selectedNodeId, newPosition);
          }
          return;
        }
      }

      // Ctrl+A - انتخاب همه (فعلاً فقط اولین node را انتخاب می‌کند)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyA) {
        if (_editorState.nodes.isNotEmpty) {
          _editorState.selectNode(_editorState.nodes.first.id);
        }
        return;
      }
    }
  }

  void _deleteSelectedNode() {
    final selectedId = _editorState.selectedNodeId;
    if (selectedId != null) {
      final node = _editorState.getNodeById(selectedId);
      if (node != null) {
        _deleteNode(node);
      }
    }
  }

  void _deleteNode(WorkflowNodeModel node) {
    _editorState.removeNode(node.id);
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.workflowNodeDeleted),
          action: SnackBarAction(
            label: t.workflowUndo,
          onPressed: () {
            if (_editorState.canUndo) {
              _editorState.undo();
            }
          },
        ),
      ),
    );
  }

  void _duplicateNode(WorkflowNodeModel node) {
    final t = AppLocalizations.of(context);
    final newNode = WorkflowNodeModel(
      id: _uuid.v4(),
      type: node.type,
      label: '${node.label} (${t.workflowCopy})',
      position: Offset(node.position.dx + 50, node.position.dy + 50),
      config: Map<String, dynamic>.from(node.config),
      key: node.key,
      icon: node.icon,
    );
    // اضافه کردن node با موقعیت
    _editorState.addNodeWithPosition(newNode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.workflowNodeDuplicated),
      ),
    );
  }

}

