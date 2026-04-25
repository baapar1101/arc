import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../services/workflow_service.dart';
import '../../services/workflow_translation_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../utils/workflow_validator.dart';
import '../../utils/workflow_auto_layout.dart';
import '../../widgets/workflow/workflow_canvas.dart';
import '../../widgets/workflow/workflow_minimap.dart';
import '../../widgets/workflow/workflow_node_config_dialog.dart';
import '../../widgets/workflow/workflow_node_context_menu.dart';
import '../../widgets/workflow/workflow_node_palette.dart';
import '../../widgets/workflow/workflow_toolbar_widget.dart';
import '../../widgets/workflow/workflow_execution_history_panel.dart';
import '../../widgets/workflow/workflow_templates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/workflow/workflow_publish_to_marketplace_dialog.dart';


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
  final WorkflowTranslationService _translationService = WorkflowTranslationService();
  final WorkflowEditorState _editorState = WorkflowEditorState();
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _workflow;
  List<WorkflowNodeMetadata> _triggers = const [];
  List<WorkflowNodeMetadata> _actions = const [];
  final FocusNode _focusNode = FocusNode();
  final _uuid = const Uuid();
  WorkflowAutoLayoutType _layoutType = WorkflowAutoLayoutType.hierarchical;
  bool _testRunBusy = false;

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
      final locale = Localizations.localeOf(context);
      final lang = locale.languageCode;
      final results = await Future.wait([
        _translationService.getTriggersMetadata(lang: lang),
        _translationService.getActionsMetadata(lang: lang),
      ]);

      final triggersList = results[0] as List<dynamic>? ?? <dynamic>[];
      final triggers = <WorkflowNodeMetadata>[];
      for (final item in triggersList) {
        if (item is! Map) continue;
        try {
          final itemMap = Map<String, dynamic>.from(item.map((k, v) => MapEntry(k.toString(), v)));
          final configSchema = itemMap['config_schema'];
          triggers.add(WorkflowNodeMetadata(
            key: itemMap['key']?.toString() ?? '',
            name: itemMap['name']?.toString() ?? itemMap['key']?.toString() ?? '',
            description: itemMap['description']?.toString(),
            type: WorkflowNodeType.trigger,
            configSchema: configSchema is Map
                ? Map<String, dynamic>.from(configSchema.map((k, v) => MapEntry(k.toString(), v)))
                : null,
          ));
        } catch (e) {
          debugPrint('خطا در پردازش trigger: $e');
        }
      }

      final actionsList = results[1] as List<dynamic>? ?? <dynamic>[];
      final actions = <WorkflowNodeMetadata>[];
      for (final item in actionsList) {
        if (item is! Map) continue;
        try {
          final itemMap = Map<String, dynamic>.from(item.map((k, v) => MapEntry(k.toString(), v)));
          final configSchema = itemMap['config_schema'];
          actions.add(WorkflowNodeMetadata(
            key: itemMap['key']?.toString() ?? '',
            name: itemMap['name']?.toString() ?? itemMap['key']?.toString() ?? '',
            description: itemMap['description']?.toString(),
            type: WorkflowNodeType.action,
            configSchema: configSchema is Map
                ? Map<String, dynamic>.from(configSchema.map((k, v) => MapEntry(k.toString(), v)))
                : null,
          ));
        } catch (e) {
          debugPrint('خطا در پردازش action: $e');
        }
      }

      _triggers = triggers;
      _actions = actions;
      _editorState.loadMetadata(triggers: triggers, actions: actions);

      if (_workflow != null) {
        final workflowData = _workflow?['workflow_data'];
        if (workflowData is String) {
          try {
            final decoded = jsonDecode(workflowData);
            if (decoded is Map) {
              final decodedMap = Map<String, dynamic>.from(decoded.map((k, v) => MapEntry(k.toString(), v)));
              _editorState.loadWorkflow(decodedMap);
            } else {
              _editorState.loadWorkflow({'nodes': [], 'connections': []});
            }
          } catch (e) {
            debugPrint('خطا در decode کردن workflow_data: $e');
            _editorState.loadWorkflow({'nodes': [], 'connections': []});
          }
        } else if (workflowData is Map) {
          final workflowMap = Map<String, dynamic>.from(workflowData.map((k, v) => MapEntry(k.toString(), v)));
          _editorState.loadWorkflow(workflowMap);
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
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: t.workflowErrorLoading);
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
        // بازگشت به صفحه لیست ورکفلوها
        _goBackToWorkflowsList();
      },
      child: Scaffold(
        onEndDrawerChanged: (isOpened) {
          if (!isOpened) {
            _editorState.clearHistoryExecutionHighlight();
          }
        },
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: _goBackToWorkflowsList,
          ),
          actions: [
            // دکمه ویرایش نام و توضیحات
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _loading ? null : _editWorkflowInfo,
              tooltip: t.workflowEditNameDescription,
            ),
            // دکمه تاریخچه اجرا (فقط برای workflowهای ذخیره شده)
            if (_workflow != null && _workflow!['id'] != null)
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                tooltip: t.workflowExecutionHistory,
              ),
            if (_workflow != null && _workflow!['id'] != null)
              IconButton(
                icon: const Icon(Icons.cloud_upload_outlined),
                onPressed: _loading ? null : _publishToMarketplace,
                tooltip: t.workflowMarketplacePublish,
              ),
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
        child: Builder(
          builder: (context) => WorkflowNodePaletteContent(
            triggers: _triggers,
            actions: _actions,
            onNodeSelected: (type, key, name) {
              try {
                _editorState.addNode(type, key, name);
                // بستن drawer بدون pop کردن صفحه
                Scaffold.of(context).closeDrawer();
              } catch (e, stackTrace) {
                debugPrint('خطا در افزودن نود: $e');
                debugPrint('StackTrace: $stackTrace');
                if (mounted) {
                  SnackBarHelper.showError(
                    context,
                    message:
                        '${t.workflowErrorAddNode}: ${ErrorExtractor.forContext(e, context)}',
                  );
                }
              }
            },
          ),
        ),
      ),
      endDrawer: _workflow != null && _workflow!['id'] != null
          ? Drawer(
              width: math.min(400, MediaQuery.sizeOf(context).width * 0.92),
              child: WorkflowExecutionHistoryPanel(
                businessId: widget.businessId,
                workflowId: _workflow!['id'] as int,
                nodes: _editorState.nodes,
                onExecutedNodesHighlight: (ids) {
                  if (ids.isEmpty) {
                    _editorState.clearHistoryExecutionHighlight();
                  } else {
                    _editorState.setHistoryExecutionHighlight(ids);
                  }
                },
                onClearCanvasHighlight: () {
                  _editorState.clearHistoryExecutionHighlight();
                },
              ),
            )
          : null,
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
                        onSaveAsTemplate: () {
                          _saveAsTemplate();
                        },
                        onLoadTemplate: () {
                          _loadTemplate();
                        },
                        onTestRun: _canLiveTestRun ? _runLiveTestWorkflow : null,
                        testRunEnabled: _canLiveTestRun,
                        testRunBusy: _testRunBusy,
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
                                allNodes: _editorState.nodes,
                                businessId: widget.businessId,
                              ),
                            );
                            if (result != null) {
                              _editorState.updateNodeConfig(node.id, result);
                            }
                          },
                          onNodeLongPress: (node, position) async {
                            await WorkflowNodeContextMenu.show(
                              context,
                              position,
                              node: node,
                              onEditComment: () {
                                if (mounted) _editNodeComment(node);
                              },
                              onEdit: () async {
                                if (!mounted) return;
                                final result = await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (_) => WorkflowNodeConfigDialog(
                                    node: node,
                                    editorState: _editorState,
                                    allNodes: _editorState.nodes,
                                    businessId: widget.businessId,
                                  ),
                                );
                                if (result != null && mounted) {
                                  _editorState.updateNodeConfig(node.id, result);
                                }
                              },
                              onDuplicate: () {
                                if (mounted) _duplicateNode(node);
                              },
                              onDelete: () {
                                if (mounted) _deleteNode(node);
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

  bool _executionWasDryRun(Map<String, dynamic>? ex) {
    if (ex == null) return false;
    final ed = ex['execution_data'];
    if (ed is! Map) return false;
    return Map<String, dynamic>.from(
      ed.map((k, v) => MapEntry(k.toString(), v)),
    )['dry_run'] == true;
  }

  bool get _canLiveTestRun {
    if (_workflow == null || _workflow!['id'] == null) return false;
    final s = _workflow!['status']?.toString();
    return s == 'فعال';
  }

  void _applyLiveRunLogEntry(Map<String, dynamic> log) {
    final level = log['level']?.toString().toLowerCase();
    final dataRaw = log['data'];
    if (dataRaw is! Map) return;
    final data = Map<String, dynamic>.from(
      dataRaw.map((k, v) => MapEntry(k.toString(), v)),
    );
    final nodeId = data['node_id']?.toString();
    if (nodeId == null || nodeId.isEmpty) return;

    final event = data['event']?.toString();
    if (event == 'node_started') {
      _editorState.onLiveRunLogNodeStarted(nodeId);
      return;
    }
    if (level == 'error' && data['success'] == false) {
      _editorState.onLiveRunLogNodeError(nodeId);
      return;
    }
    if (data['success'] == true) {
      _editorState.onLiveRunLogNodeSuccess(nodeId);
    }
  }

  Future<void> _runLiveTestWorkflow() async {
    if (_testRunBusy || !_canLiveTestRun) return;
    final t = AppLocalizations.of(context);
    final wid = _workflow!['id'] as int;

    final errors = WorkflowValidator.validateWorkflow(
      nodes: _editorState.nodes,
      connections: _editorState.connections,
      context: context,
    );
    if (errors.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.workflowValidationError),
          content: Text(t.workflowFixValidationBeforeTestRun),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.workflowClose)),
          ],
        ),
      );
      return;
    }

    setState(() => _testRunBusy = true);
    _editorState.beginLiveRun();

    try {
      final exec = await _workflowService.executeWorkflow(
        businessId: widget.businessId,
        workflowId: wid,
        triggerData: const <String, dynamic>{},
        asyncExecution: true,
        dryRun: true,
      );
      final executionId = exec['id'];
      if (executionId is! int) {
        throw StateError('execution id missing');
      }

      var lastLogId = 0;
      Map<String, dynamic>? lastExecution;

      while (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 350));

        final logs = await _workflowService.getExecutionLogs(
          businessId: widget.businessId,
          workflowId: wid,
          executionId: executionId,
          afterLogId: lastLogId,
        );
        for (final log in logs) {
          final id = log['id'];
          if (id is int && id > lastLogId) {
            lastLogId = id;
          }
          _applyLiveRunLogEntry(Map<String, dynamic>.from(log.map((k, v) => MapEntry(k.toString(), v))));
        }

        lastExecution = await _workflowService.getWorkflowExecution(
          businessId: widget.businessId,
          workflowId: wid,
          executionId: executionId,
        );
        final st = lastExecution['status']?.toString() ?? '';
        if (st == WorkflowExecutionStatusValue.completed ||
            st == WorkflowExecutionStatusValue.failed ||
            st == WorkflowExecutionStatusValue.cancelled) {
          break;
        }
      }

      if (!mounted) return;

      final st = lastExecution?['status']?.toString() ?? '';
      if (st == WorkflowExecutionStatusValue.completed) {
        final dry = _executionWasDryRun(lastExecution);
        SnackBarHelper.show(
          context,
          message: dry ? t.workflowTestRunCompletedDry : t.workflowExecuted,
        );
      } else if (st == WorkflowExecutionStatusValue.failed) {
        final err = lastExecution?['error_message']?.toString();
        SnackBarHelper.showError(
          context,
          message: err != null && err.isNotEmpty ? err : t.workflowErrorExecuting,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('خطا در اجرای آزمایشی workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) {
        SnackBarHelper.showError(context, message: t.workflowErrorExecuting);
      }
    } finally {
      _editorState.finishLiveRun();
      if (mounted) {
        setState(() => _testRunBusy = false);
      }
    }
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
    SnackBarHelper.show(context, message: layoutType == WorkflowAutoLayoutType.hierarchical
              ? t.workflowHierarchicalLayoutApplied
              : t.workflowForceDirectedLayoutApplied,);
  }

  void _goBackToWorkflowsList() {
    context.goNamed(
      'business_workflows',
      pathParameters: {
        'business_id': widget.businessId.toString(),
      },
    );
  }

  Future<void> _editWorkflowInfo() async {
    final t = AppLocalizations.of(context);
    final nameController = TextEditingController(
      text: _workflow?['name'] ?? '',
    );
    final descriptionController = TextEditingController(
      text: _workflow?['description'] ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.workflowEditNameDescription),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: t.workflowNameRequired,
                  hintText: t.workflowNameHint,
                  prefixIcon: const Icon(Icons.label),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: t.workflowDescription,
                  hintText: t.workflowDescriptionHint,
                  prefixIcon: const Icon(Icons.description),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final workflowName = nameController.text.trim();
    if (workflowName.isEmpty) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.workflowEnterName);
      return;
    }

    // به‌روزرسانی اطلاعات محلی
    setState(() {
      if (_workflow == null) {
        _workflow = {
          'name': workflowName,
          'description': descriptionController.text.trim(),
        };
      } else {
        _workflow = {
          ..._workflow!,
          'name': workflowName,
          'description': descriptionController.text.trim(),
        };
      }
    });

    if (!mounted) return;
    SnackBarHelper.show(context, message: t.workflowInfoUpdated);
  }

  Future<void> _saveWorkflow() async {
    if (_saving) return;
    final t = AppLocalizations.of(context);

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

    // نمایش دیالوگ برای تعیین نام و توضیحات
    final nameController = TextEditingController(
      text: _workflow?['name'] ?? '',
    );
    final descriptionController = TextEditingController(
      text: _workflow?['description'] ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.workflowSaveWorkflow),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: t.workflowNameRequired,
                  hintText: t.workflowNameHint,
                  prefixIcon: const Icon(Icons.label),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: t.workflowDescription,
                  hintText: t.workflowDescriptionHint,
                  prefixIcon: const Icon(Icons.description),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.save),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final workflowName = nameController.text.trim();
    if (workflowName.isEmpty) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.workflowEnterName);
      return;
    }

    setState(() => _saving = true);
    try {
      // استفاده از enum value به جای localization string
      final statusValue = _workflow?['status'] ?? 'پیش‌نویس'; // استفاده از enum value
      
      final payload = {
        'name': workflowName,
        'description': descriptionController.text.trim().isEmpty 
            ? null 
            : descriptionController.text.trim(),
        'status': statusValue,
        'workflow_data': _editorState.toBackendFormat(),
      };

      if (_workflow == null) {
        final result = await _workflowService.createWorkflow(
          businessId: widget.businessId,
          payload: payload,
        );
        // به‌روزرسانی _workflow با نتیجه دریافتی
        if (result is Map<String, dynamic>) {
          setState(() {
            _workflow = result;
          });
        }
      } else {
        await _workflowService.updateWorkflow(
          businessId: widget.businessId,
          workflowId: _workflow!['id'] as int,
          payload: payload,
        );
        // به‌روزرسانی نام و توضیحات در _workflow
        setState(() {
          _workflow = {
            ..._workflow!,
            'name': workflowName,
            'description': descriptionController.text.trim(),
          };
        });
      }

      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showSuccess(context, message: t.workflowSaved);
      // بازگشت به صفحه لیست ورکفلوها
      context.goNamed(
        'business_workflows',
        pathParameters: {
          'business_id': widget.businessId.toString(),
        },
      );
    } catch (e, stackTrace) {
      debugPrint('خطا در ذخیره‌سازی workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.workflowErrorSaving);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _publishToMarketplace() async {
    final t = AppLocalizations.of(context);
    final rawId = _workflow?['id'];
    if (rawId == null) return;
    final workflowId = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (workflowId == null) return;
    final defaultTitle = (_workflow?['name'] ?? t.workflow).toString();
    await showDialog<bool>(
      context: context,
      builder: (context) => WorkflowPublishToMarketplaceDialog(
        businessId: widget.businessId,
        workflowId: workflowId,
        defaultTitle: defaultTitle,
      ),
    );
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
        _deleteSelectedNodes();
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

      // Ctrl+C (Copy)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
        _editorState.copySelectedNodes();
        if (_editorState.selectedNodeIds.isNotEmpty) {
          SnackBarHelper.show(context, message: '${_editorState.selectedNodeIds.length} نود کپی شد');
        }
        return;
      }

      // Ctrl+X (Cut)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyX) {
        _editorState.cutSelectedNodes();
        if (_editorState.hasClipboardContent) {
          SnackBarHelper.show(context, message: '${_editorState.selectedNodeIds.length} نود برش خورد');
        }
        return;
      }

      // Ctrl+V (Paste)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyV) {
        if (_editorState.hasClipboardContent) {
          _editorState.pasteNodes();
          SnackBarHelper.show(context, message: 'نودها چسبانده شدند');
        }
        return;
      }

      // Ctrl+D (Duplicate)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
        if (_editorState.selectedNodeId != null) {
          final node = _editorState.getNodeById(_editorState.selectedNodeId!);
          if (node != null) {
            _duplicateNode(node);
          }
        }
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

      // Ctrl+A - انتخاب همه نودها
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyA) {
        if (_editorState.nodes.isNotEmpty) {
          _editorState.selectMultipleNodes(
            _editorState.nodes.map((n) => n.id).toList()
          );
        }
        return;
      }

      // Escape - لغو انتخاب چندگانه
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_editorState.selectedNodeIds.isNotEmpty) {
          _editorState.selectNode(null);
        }
        return;
      }
    }
  }

  void _deleteSelectedNodes() {
    final t = AppLocalizations.of(context);
    
    if (_editorState.selectedNodeIds.isEmpty) {
      return;
    }
    
    if (_editorState.selectedNodeIds.length == 1) {
      // حذف تک نود
      final selectedId = _editorState.selectedNodeIds.first;
      final node = _editorState.getNodeById(selectedId);
      if (node != null) {
        _deleteNode(node);
      }
    } else {
      // حذف چند نود
      final count = _editorState.selectedNodeIds.length;
      _editorState.deleteSelectedNodes();
      
      SnackBarHelper.show(context, message: '$count ${t.workflowNodeDeleted}');
    }
  }

  void _deleteNode(WorkflowNodeModel node) {
    _editorState.removeNode(node.id);
    final t = AppLocalizations.of(context);
    SnackBarHelper.show(context, message: t.workflowNodeDeleted);
  }

  void _duplicateNode(WorkflowNodeModel node) {
    final t = AppLocalizations.of(context);
    
    // پیدا کردن موقعیت خالی نزدیک به node اصلی
    final targetPosition = Offset(node.position.dx + 50, node.position.dy + 50);
    final newPosition = _editorState.findNearestEmptyPosition(targetPosition);
    
    final newNode = WorkflowNodeModel(
      id: _uuid.v4(),
      type: node.type,
      label: '${node.label} (${t.workflowCopy})',
      position: newPosition,
      config: Map<String, dynamic>.from(node.config),
      key: node.key,
      icon: node.icon,
      comment: node.comment,
    );
    // اضافه کردن node با موقعیت
    _editorState.addNodeWithPosition(newNode);
    SnackBarHelper.show(context, message: t.workflowNodeDuplicated);
  }

  void _editNodeComment(WorkflowNodeModel node) {
    final t = AppLocalizations.of(context);
    final commentController = TextEditingController(text: node.comment ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.workflowNoteComment),
        content: TextField(
          controller: commentController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: t.workflowNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          if (node.comment != null && node.comment!.isNotEmpty)
            TextButton(
              onPressed: () {
                final index = _editorState.nodes.indexWhere((n) => n.id == node.id);
                if (index != -1) {
                  _editorState.updateNodeConfig(node.id, {...node.config});
                  // حذف comment با copyWith
                  final updatedNode = _editorState.nodes[index].copyWith(comment: '');
                  _editorState.nodes.removeAt(index);
                  _editorState.addNodeWithPosition(updatedNode);
                }
                Navigator.pop(context);
                SnackBarHelper.show(context, message: t.workflowNoteDeleted);
              },
              child: Text(t.delete, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () {
              final newComment = commentController.text.trim();
              final index = _editorState.nodes.indexWhere((n) => n.id == node.id);
              if (index != -1) {
                final updatedNode = _editorState.nodes[index].copyWith(
                  comment: newComment.isEmpty ? null : newComment,
                );
                _editorState.nodes.removeAt(index);
                _editorState.addNodeWithPosition(updatedNode);
              }
              Navigator.pop(context);
              SnackBarHelper.show(context, message: newComment.isEmpty 
                      ? t.workflowNoteCleared 
                      : t.workflowNoteSaved);
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsTemplate() async {
    final t = AppLocalizations.of(context);
    final nameController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.workflowSaveAsTemplate),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: t.workflowTemplateName,
            hintText: t.workflowTemplateNameHint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.save),
          ),
        ],
      ),
    );
    
    if (confirmed != true || nameController.text.trim().isEmpty) return;
    
    // نمایش loading indicator (روی root navigator تا با ShellRoute تداخل نگیرد)
    if (!mounted) return;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final templateName = nameController.text.trim();
      final workflowData = _editorState.toBackendFormat();
      final templateData = {
        'name': templateName,
        'workflow_data': workflowData,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // ذخیره در shared preferences
      final templatesKey = 'workflow_templates_${widget.businessId}';
      final templatesJson = prefs.getString(templatesKey) ?? '[]';
      final templates = List<Map<String, dynamic>>.from(
        jsonDecode(templatesJson).map((t) => Map<String, dynamic>.from(t))
      );
      templates.add(templateData);
      
      await prefs.setString(templatesKey, jsonEncode(templates));
      
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // بستن loading indicator
        SnackBarHelper.show(context, message: t.workflowTemplateSaved(templateName));
      }
    } catch (e) {
      debugPrint('خطا در ذخیره template: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // بستن loading indicator
        SnackBarHelper.showError(
          context,
          message:
              '${t.workflowErrorSaveTemplate}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  Future<void> _loadTemplate() async {
    final t = AppLocalizations.of(context);
    if (!mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    var loadingOpen = true;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final builtInTemplates = WorkflowTemplates.getLocalizedTemplates(t);
      
      // دریافت قالب‌های ذخیره شده کاربر
      final prefs = await SharedPreferences.getInstance();
      final templatesKey = 'workflow_templates_${widget.businessId}';
      final templatesJson = prefs.getString(templatesKey) ?? '[]';
      final savedTemplates = List<Map<String, dynamic>>.from(
        jsonDecode(templatesJson).map((e) => Map<String, dynamic>.from(e as Map))
      );
      
      if (!mounted) return;
      rootNav.pop();
      loadingOpen = false;
      
      // نمایش لیست قالب‌ها
      final selectedTemplate = await showDialog<Map<String, dynamic>>(
        context: context,
        useRootNavigator: true,
        builder: (context) => _TemplateSelectorDialog(
          builtInTemplates: builtInTemplates,
          savedTemplates: savedTemplates,
          onDeleteSaved: (index) async {
            savedTemplates.removeAt(index);
            await prefs.setString(templatesKey, jsonEncode(savedTemplates));
            Navigator.pop(context);
            _loadTemplate(); // بارگذاری مجدد
          },
        ),
      );
      
      if (selectedTemplate != null) {
        final raw = selectedTemplate['workflow_data'] ?? selectedTemplate['workflow'];
        Map<String, dynamic>? workflowData;
        if (raw is Map<String, dynamic>) {
          workflowData = raw;
        } else if (raw is Map) {
          workflowData = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
        }
        
        if (workflowData != null) {
          _editorState.loadWorkflow(workflowData);
          if (mounted) {
            SnackBarHelper.show(context, message: t.workflowTemplateLoaded(selectedTemplate['name']?.toString() ?? t.workflowTemplateDefault));
          }
        }
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری template: $e');
      if (mounted) {
        if (loadingOpen) {
          rootNav.pop();
        }
        SnackBarHelper.show(
          context,
          message:
              '${t.workflowErrorLoadTemplate}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

}

/// Dialog برای انتخاب Template
class _TemplateSelectorDialog extends StatelessWidget {
  final List<WorkflowTemplate> builtInTemplates;
  final List<Map<String, dynamic>> savedTemplates;
  final Function(int) onDeleteSaved;

  const _TemplateSelectorDialog({
    required this.builtInTemplates,
    required this.savedTemplates,
    required this.onDeleteSaved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    
    return AlertDialog(
      title: Text(t.workflowSelectTemplate),
      content: SizedBox(
        width: 500,
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                tabs: [
                  Tab(text: t.workflowBuiltinTemplates),
                  Tab(text: t.workflowSavedTemplates),
                ],
              ),
              SizedBox(
                height: 400,
                child: TabBarView(
                  children: [
                    // قالب‌های آماده
                    ListView.builder(
                      itemCount: builtInTemplates.length,
                      itemBuilder: (context, index) {
                        final template = builtInTemplates[index];
                        return ListTile(
                          leading: Icon(template.icon, color: theme.colorScheme.primary),
                          title: Text(template.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(template.description),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  template.category,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
                          onTap: () => Navigator.pop(context, {
                            'is_builtin': true,
                            'name': template.name,
                            'workflow_data': template.workflowData,
                          }),
                        );
                      },
                    ),
                    // قالب‌های ذخیره شده
                    savedTemplates.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  t.workflowNoSavedTemplates,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: savedTemplates.length,
                            itemBuilder: (context, index) {
                              final template = savedTemplates[index];
                              return ListTile(
                                leading: const Icon(Icons.insert_drive_file),
                                title: Text(template['name'] ?? t.workflowTemplateN(index + 1)),
                                subtitle: Text(template['created_at'] != null
                                    ? t.workflowCreatedAt(template['created_at'].toString())
                                    : ''),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => onDeleteSaved(index),
                                ),
                                onTap: () => Navigator.pop(context, {
                                  'is_builtin': false,
                                  'name': template['name'],
                                  'workflow_data':
                                      template['workflow_data'] ?? template['workflow'],
                                }),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}

