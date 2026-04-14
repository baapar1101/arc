import 'package:flutter/material.dart';
import '../models/workflow_editor_models.dart';
import '../models/workflow_editor_state.dart';

/// Command interface برای undo/redo
abstract class WorkflowCommand {
  void execute();
  void undo();
}

/// Command برای افزودن node
class AddNodeCommand implements WorkflowCommand {
  final WorkflowEditorState state;
  final WorkflowNodeModel node;

  AddNodeCommand(this.state, this.node);

  @override
  void execute() {
    // در state manager خودش node را اضافه می‌کند
  }

  @override
  void undo() {
    state.removeNode(node.id, trackHistory: false);
    state.notifyListeners();
  }
}

/// Command برای حذف node
class RemoveNodeCommand implements WorkflowCommand {
  final WorkflowEditorState state;
  final WorkflowNodeModel node;
  final List<WorkflowConnectionModel> connections;

  RemoveNodeCommand(this.state, this.node, this.connections);

  @override
  void execute() {
    state.removeNode(node.id, trackHistory: false);
  }

  @override
  void undo() {
    state.addNodeWithoutHistory(node, connections);
    state.notifyListeners();
  }
}

/// Command برای جابجایی node
class MoveNodeCommand implements WorkflowCommand {
  final WorkflowEditorState state;
  final String nodeId;
  final Offset oldPosition;
  final Offset newPosition;

  MoveNodeCommand(this.state, this.nodeId, this.oldPosition, this.newPosition);

  @override
  void execute() {
    state.updateNodePositionWithoutHistory(nodeId, newPosition);
    state.notifyListeners();
  }

  @override
  void undo() {
    state.updateNodePositionWithoutHistory(nodeId, oldPosition);
    state.notifyListeners();
  }
}

/// Command برای افزودن connection
class AddConnectionCommand implements WorkflowCommand {
  final WorkflowEditorState state;
  final WorkflowConnectionModel connection;

  AddConnectionCommand(this.state, this.connection);

  @override
  void execute() {
    // در state manager خودش connection را اضافه می‌کند
  }

  @override
  void undo() {
    state.removeConnection(connection.id);
  }
}

/// History Manager برای undo/redo
class WorkflowHistory {
  final List<WorkflowCommand> _history = [];
  int _currentIndex = -1;
  static const int _maxHistorySize = 50;

  /// اضافه کردن command به history
  void addCommand(WorkflowCommand command) {
    // حذف command های بعد از current index (وقتی undo شده)
    if (_currentIndex < _history.length - 1) {
      _history.removeRange(_currentIndex + 1, _history.length);
    }

    _history.add(command);
    _currentIndex = _history.length - 1;

    // محدود کردن سایز history
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
      _currentIndex--;
    }
  }

  /// Undo
  bool undo() {
    if (!canUndo()) return false;
    _history[_currentIndex].undo();
    _currentIndex--;
    return true;
  }

  /// Redo
  bool redo() {
    if (!canRedo()) return false;
    _currentIndex++;
    _history[_currentIndex].execute();
    return true;
  }

  /// آیا می‌توان undo کرد؟
  bool canUndo() => _currentIndex >= 0;

  /// آیا می‌توان redo کرد؟
  bool canRedo() => _currentIndex < _history.length - 1;

  /// پاک کردن history
  void clear() {
    _history.clear();
    _currentIndex = -1;
  }
}

