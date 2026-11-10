import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaProcessDesignerPage extends StatefulWidget {
  final int businessId;

  const OaProcessDesignerPage({super.key, required this.businessId});

  @override
  State<OaProcessDesignerPage> createState() => _OaProcessDesignerPageState();
}

class _OaProcessDesignerPageState extends State<OaProcessDesignerPage> {
  static const _nodeWidth = 176.0;
  static const _nodeHeight = 72.0;
  static const _singleOut = {'start', 'user_task', 'timer', 'subprocess', 'parallel_join'};

  final OfficeAutomationService _svc = OfficeAutomationService();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  bool _loading = true;
  bool _saving = false;
  int? _definitionId;
  int _seq = 1;
  String? _selectedId;
  String? _linkFrom;
  List<Map<String, dynamic>> _drafts = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _versions = [];
  List<_FlowNode> _nodes = [];
  List<_FlowEdge> _edges = [];

  @override
  void initState() {
    super.initState();
    _seed();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(String key, String value) {
    return _fields.putIfAbsent(key, () => TextEditingController(text: value));
  }

  void _clearFields() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
  }

  void _seed() {
    _clearFields();
    _nodes = [
      _FlowNode(id: 'start', type: 'start', x: 48, y: 160),
      _FlowNode(id: 'end', type: 'end', x: 520, y: 160),
    ];
    _edges = [_FlowEdge(from: 'start', to: 'end')];
    _selectedId = 'start';
    _definitionId = null;
    _seq = 1;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final drafts = await _svc.listProcessDefinitions(businessId: widget.businessId);
      final positions = await _svc.listPositions(businessId: widget.businessId);
      final versions = await _svc.listProcessVersions(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _positions = positions;
        _versions = versions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _openDraft(Map<String, dynamic> draft) {
    _clearFields();
    final graph = draft['graph'];
    final rawNodes = graph is Map ? graph['nodes'] : null;
    final rawEdges = graph is Map ? graph['edges'] : null;
    final nodes = rawNodes is List
        ? rawNodes.whereType<Map>().map((e) => _FlowNode.fromJson(Map<String, dynamic>.from(e))).toList()
        : <_FlowNode>[];
    final edges = rawEdges is List
        ? rawEdges.whereType<Map>().map((e) => _FlowEdge.fromJson(Map<String, dynamic>.from(e))).toList()
        : <_FlowEdge>[];
    if (nodes.isEmpty) {
      _seed();
      _code.text = '${draft['code'] ?? ''}';
      _name.text = '${draft['name'] ?? ''}';
      _definitionId = oaId(draft['id']);
      setState(() {});
      return;
    }
    setState(() {
      _nodes = nodes;
      _edges = edges;
      _definitionId = oaId(draft['id']);
      _selectedId = nodes.first.id;
      _linkFrom = null;
      _code.text = '${draft['code'] ?? ''}';
      _name.text = '${draft['name'] ?? ''}';
    });
  }

  _FlowNode? get _selected {
    for (final node in _nodes) {
      if (node.id == _selectedId) return node;
    }
    return null;
  }

  void _add(String type) {
    if (type == 'start' && _nodes.any((node) => node.type == 'start')) return;
    final id = type == 'end' && !_nodes.any((node) => node.id == 'end') ? 'end' : 'n${_seq++}';
    final node = _FlowNode(id: id, type: type, x: 80 + (_nodes.length % 4) * 210, y: 80 + (_nodes.length ~/ 4) * 120);
    if (type == 'user_task') {
      node.name = id;
      node.formKey = 'note';
    }
    if (type == 'exclusive') node.field = 'decision';
    if (type == 'timer') node.hours = 1;
    setState(() {
      _nodes.add(node);
      _selectedId = id;
    });
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null || id == 'start') return;
    setState(() {
      _fields.removeWhere((key, controller) {
        final drop = key.startsWith('$id|') || key.contains('|$id|');
        if (drop) controller.dispose();
        return drop;
      });
      _nodes.removeWhere((node) => node.id == id);
      _edges.removeWhere((edge) => edge.from == id || edge.to == id);
      _selectedId = _nodes.isEmpty ? null : _nodes.first.id;
      _linkFrom = null;
    });
  }

  void _connect(String targetId) {
    final from = _linkFrom;
    if (from == null || from == targetId) {
      setState(() => _linkFrom = null);
      return;
    }
    final source = _nodes.cast<_FlowNode?>().firstWhere((node) => node?.id == from, orElse: () => null);
    if (source == null || source.type == 'end') {
      setState(() => _linkFrom = null);
      return;
    }
    setState(() {
      if (_singleOut.contains(source.type)) {
        _edges.removeWhere((edge) => edge.from == from);
      }
      final edge = _FlowEdge(from: from, to: targetId);
      if (source.type == 'exclusive' && !_edges.any((item) => item.from == from && item.isDefault)) {
        edge.isDefault = true;
      }
      _edges.add(edge);
      _linkFrom = null;
      _selectedId = targetId;
    });
  }

  Map<String, dynamic> _graph() {
    return {
      'nodes': [for (final node in _nodes) node.toJson()],
      'edges': [for (final edge in _edges) edge.toJson()],
    };
  }

  Future<void> _save({bool publish = false}) async {
    final t = AppLocalizations.of(context);
    final code = _code.text.trim();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      SnackBarHelper.showError(context, message: t.oaProcessCodeName);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await _svc.saveProcessDraft(
        businessId: widget.businessId,
        code: code,
        name: name,
        graph: _graph(),
      );
      final id = oaId(saved['id']);
      Map<String, dynamic>? published;
      if (publish && id != null) {
        published = await _svc.publishProcess(businessId: widget.businessId, definitionId: id);
      }
      if (!mounted) return;
      setState(() {
        _definitionId = id;
        _saving = false;
      });
      SnackBarHelper.showSuccess(
        context,
        message: published == null ? t.oaSaveDraft : '${t.oaPublishProcess} ${published['version_no'] ?? ''}',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaProcessDesigner),
        actions: [
          IconButton(tooltip: t.oaNewProcess, onPressed: () => setState(_seed), icon: const Icon(Icons.note_add_outlined)),
          IconButton(tooltip: t.refresh, onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          initialValue: _definitionId != null && _drafts.any((d) => oaId(d['id']) == _definitionId) ? _definitionId : null,
                          decoration: InputDecoration(labelText: t.oaProcessDrafts, border: const OutlineInputBorder(), isDense: true),
                          items: [
                            for (final draft in _drafts)
                              if (oaId(draft['id']) != null)
                                DropdownMenuItem(value: oaId(draft['id']), child: Text('${draft['name'] ?? draft['code']}', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (id) {
                            final draft = _drafts.cast<Map<String, dynamic>?>().firstWhere((row) => oaId(row?['id']) == id, orElse: () => null);
                            if (draft != null) _openDraft(draft);
                          },
                        ),
                      ),
                      SizedBox(width: 160, child: TextField(controller: _code, decoration: InputDecoration(labelText: t.oaProcessCode, border: const OutlineInputBorder(), isDense: true))),
                      SizedBox(width: 200, child: TextField(controller: _name, decoration: InputDecoration(labelText: t.oaProcessName, border: const OutlineInputBorder(), isDense: true))),
                      for (final type in const ['user_task', 'exclusive', 'parallel_split', 'parallel_join', 'timer', 'subprocess', 'end'])
                        ActionChip(label: Text(_typeLabel(t, type)), onPressed: () => _add(type)),
                      FilledButton.tonal(onPressed: _saving ? null : () => _save(), child: Text(t.oaSaveDraft)),
                      FilledButton(onPressed: _saving ? null : () => _save(publish: true), child: Text(t.oaPublishProcess)),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _canvas(scheme, t)),
                      SizedBox(width: 320, child: _inspector(t)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _canvas(ColorScheme scheme, AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.5,
            maxScale: 2,
            boundaryMargin: const EdgeInsets.all(800),
            child: SizedBox(
              width: 1400,
              height: 860,
              child: Stack(
                children: [
                  CustomPaint(size: const Size(1400, 860), painter: _EdgePainter(nodes: _nodes, edges: _edges, color: scheme.outline)),
                  for (final node in _nodes)
                    Positioned(
                      left: node.x,
                      top: node.y,
                      child: GestureDetector(
                        onTap: () {
                          if (_linkFrom != null) {
                            _connect(node.id);
                          } else {
                            setState(() => _selectedId = node.id);
                          }
                        },
                        onPanUpdate: (details) => setState(() {
                          node.x = (node.x + details.delta.dx).clamp(0, 1220).toDouble();
                          node.y = (node.y + details.delta.dy).clamp(0, 780).toDouble();
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _nodeWidth,
                          height: _nodeHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: node.id == _selectedId
                                  ? scheme.primary
                                  : node.id == _linkFrom
                                      ? scheme.tertiary
                                      : scheme.outlineVariant,
                              width: node.id == _selectedId ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_typeLabel(t, node.type), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              Text(node.name.isEmpty ? node.id : node.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inspector(AppLocalizations t) {
    final node = _selected;
    final outgoing = node == null ? <_FlowEdge>[] : _edges.where((edge) => edge.from == node.id).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
      children: [
        Text(t.oaProcessInspector, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (node == null)
          Text(t.oaSelectNode)
        else ...[
          Text('${_typeLabel(t, node.type)} · ${node.id}'),
          const SizedBox(height: 8),
          if (node.type == 'user_task' || node.type == 'exclusive' || node.type == 'timer' || node.type == 'subprocess')
            TextField(
              controller: _field('${node.id}|name', node.name),
              decoration: InputDecoration(labelText: t.oaProcessName, border: const OutlineInputBorder(), isDense: true),
              onChanged: (value) => node.name = value,
            ),
          if (node.type == 'user_task') ...[
            const SizedBox(height: 8),
            _positionField(t.oaAssignee, node.assigneeId, (id) => setState(() => node.assigneeId = id)),
            const SizedBox(height: 8),
            _positionField(t.oaEscalateTo, node.escalateId, (id) => setState(() => node.escalateId = id)),
            const SizedBox(height: 8),
            TextField(
              controller: _field('${node.id}|sla', node.slaHours > 0 ? '${node.slaHours}' : ''),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.oaSlaHours, border: const OutlineInputBorder(), isDense: true),
              onChanged: (value) => node.slaHours = int.tryParse(value) ?? 0,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _field('${node.id}|form', node.formLabel),
              decoration: InputDecoration(labelText: t.oaFormLabel, border: const OutlineInputBorder(), isDense: true),
              onChanged: (value) => node.formLabel = value,
            ),
          ],
          if (node.type == 'exclusive') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _field('${node.id}|field', node.field),
              decoration: InputDecoration(labelText: t.oaGatewayField, border: const OutlineInputBorder(), isDense: true),
              onChanged: (value) => node.field = value,
            ),
          ],
          if (node.type == 'timer') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _field('${node.id}|hours', '${node.hours}'),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.oaTimerHours, border: const OutlineInputBorder(), isDense: true),
              onChanged: (value) => node.hours = int.tryParse(value) ?? 0,
            ),
          ],
          if (node.type == 'subprocess') ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _versions.any((row) => oaId(row['id']) == node.versionId) ? node.versionId : null,
              decoration: InputDecoration(labelText: t.oaSubprocessVersion, border: const OutlineInputBorder(), isDense: true),
              items: [
                for (final version in _versions)
                  if (oaId(version['id']) != null)
                    DropdownMenuItem(value: oaId(version['id']), child: Text('${version['name'] ?? ''} ${version['version_no'] ?? ''}')),
              ],
              onChanged: (id) => setState(() => node.versionId = id),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (node.type != 'end')
                OutlinedButton(
                  onPressed: () => setState(() => _linkFrom = node.id),
                  child: Text(_linkFrom == node.id ? t.oaPickTarget : t.oaConnectNodes),
                ),
              if (node.id != 'start') TextButton(onPressed: _deleteSelected, child: Text(t.oaDeleteNode)),
            ],
          ),
          for (final edge in outgoing) ...[
            const SizedBox(height: 8),
            Text('${edge.from} → ${edge.to}'),
            if (node.type == 'exclusive')
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _field('edge|${edge.from}|${edge.to}|when', edge.when),
                      decoration: InputDecoration(labelText: t.oaEdgeWhen, border: const OutlineInputBorder(), isDense: true),
                      onChanged: (value) => edge.when = value,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(t.oaEdgeDefault),
                    selected: edge.isDefault,
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        for (final item in _edges.where((item) => item.from == edge.from)) {
                          item.isDefault = false;
                        }
                      }
                      edge.isDefault = selected;
                    }),
                  ),
                ],
              ),
          ],
        ],
      ],
    );
  }

  Widget _positionField(String label, int? value, ValueChanged<int?> onChanged) {
    final known = _positions.any((row) => oaId(row['id']) == value);
    return DropdownButtonFormField<int>(
      initialValue: known ? value : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: [
        for (final position in _positions)
          if (oaId(position['id']) != null) DropdownMenuItem(value: oaId(position['id']), child: Text(oaPositionLabel(position), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  String _typeLabel(AppLocalizations t, String type) {
    switch (type) {
      case 'start':
        return t.oaNodeStart;
      case 'user_task':
        return t.oaNodeTask;
      case 'exclusive':
        return t.oaNodeExclusive;
      case 'parallel_split':
        return t.oaNodeSplit;
      case 'parallel_join':
        return t.oaNodeJoin;
      case 'timer':
        return t.oaNodeTimer;
      case 'subprocess':
        return t.oaNodeSubprocess;
      default:
        return t.oaNodeEnd;
    }
  }
}

class _FlowNode {
  _FlowNode({required this.id, required this.type, required this.x, required this.y});

  final String id;
  final String type;
  double x;
  double y;
  String name = '';
  int? assigneeId;
  int? escalateId;
  int slaHours = 0;
  String formKey = '';
  String formLabel = '';
  bool formRequired = true;
  String field = '';
  int hours = 1;
  int? versionId;

  factory _FlowNode.fromJson(Map<String, dynamic> json) {
    final node = _FlowNode(
      id: '${json['id']}',
      type: '${json['type'] ?? 'end'}',
      x: (json['x'] as num?)?.toDouble() ?? 48,
      y: (json['y'] as num?)?.toDouble() ?? 48,
    );
    node.name = '${json['name'] ?? ''}';
    node.assigneeId = oaId(json['assignee_position_id']);
    node.escalateId = oaId(json['escalate_position_id']);
    node.slaHours = (json['sla_hours'] as num?)?.toInt() ?? 0;
    node.field = '${json['field'] ?? ''}';
    node.hours = (json['hours'] as num?)?.toInt() ?? 1;
    node.versionId = oaId(json['version_id']);
    final form = json['form'];
    if (form is List && form.isNotEmpty && form.first is Map) {
      final first = Map<String, dynamic>.from(form.first as Map);
      node.formKey = '${first['key'] ?? 'note'}';
      node.formLabel = '${first['label'] ?? ''}';
      node.formRequired = first['required'] != false;
    }
    return node;
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'type': type,
      'x': x.round(),
      'y': y.round(),
    };
    if (name.isNotEmpty) json['name'] = name;
    if (type == 'user_task') {
      if (assigneeId != null) json['assignee_position_id'] = assigneeId;
      if (escalateId != null) json['escalate_position_id'] = escalateId;
      if (slaHours > 0) json['sla_hours'] = slaHours;
      if (formKey.isNotEmpty || formLabel.isNotEmpty) {
        json['form'] = [
          {'key': formKey.isEmpty ? 'note' : formKey, 'label': formLabel.isEmpty ? formKey : formLabel, 'type': 'text', 'required': formRequired},
        ];
      }
    }
    if (type == 'exclusive') json['field'] = field;
    if (type == 'timer') json['hours'] = hours;
    if (type == 'subprocess' && versionId != null) json['version_id'] = versionId;
    return json;
  }
}

class _FlowEdge {
  _FlowEdge({required this.from, required this.to, this.when = '', this.isDefault = false});

  final String from;
  final String to;
  String when;
  bool isDefault;

  factory _FlowEdge.fromJson(Map<String, dynamic> json) {
    return _FlowEdge(
      from: '${json['from']}',
      to: '${json['to']}',
      when: '${json['when'] ?? ''}',
      isDefault: json['default'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      if (when.isNotEmpty) 'when': when,
      if (isDefault) 'default': true,
    };
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.nodes, required this.edges, required this.color});

  final List<_FlowNode> nodes;
  final List<_FlowEdge> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final from = _at(edge.from);
      final to = _at(edge.to);
      if (from == null || to == null) continue;
      final start = Offset(from.x + 176, from.y + 36);
      final end = Offset(to.x, to.y + 36);
      canvas.drawLine(start, end, paint);
    }
  }

  _FlowNode? _at(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}
