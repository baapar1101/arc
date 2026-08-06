import '../../../models/barcode_label/label_design_v1.dart';

/// تاریخچه undo/redo مبتنی بر snapshot سند طراحی.
class LabelStudioHistory {
  static const int maxDepth = 60;

  final List<LabelDesignDocument> _undo = [];
  final List<LabelDesignDocument> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  /// قبل از هر تغییر معنادار صدا زده شود (وضعیت فعلی را نگه می‌دارد).
  void checkpoint(LabelDesignDocument current) {
    _undo.add(_clone(current));
    if (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  LabelDesignDocument? undo(LabelDesignDocument current) {
    if (_undo.isEmpty) return null;
    _redo.add(_clone(current));
    return _undo.removeLast();
  }

  LabelDesignDocument? redo(LabelDesignDocument current) {
    if (_redo.isEmpty) return null;
    _undo.add(_clone(current));
    return _redo.removeLast();
  }

  LabelDesignDocument _clone(LabelDesignDocument d) =>
      LabelDesignDocument.fromJson(d.toJson());
}
