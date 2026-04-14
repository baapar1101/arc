import 'dart:io';

import 'package:file_picker/file_picker.dart';

class PickedFileData {
  final String name;
  final List<int> bytes;
  PickedFileData(this.name, this.bytes);
}

class FilePickerBridge {
  static Future<PickedFileData?> pickExcel() {
    return _pickFile(extensions: const ['xlsx']);
  }

  static Future<PickedFileData?> pickXml() {
    return _pickFile(extensions: const ['xml', 'zip']);
  }

  static Future<PickedFileData?> _pickFile({required List<String> extensions}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return null;
    final pf = res.files.first;
    if (pf.path == null) return null;
    final bytes = await File(pf.path!).readAsBytes();
    return PickedFileData(pf.name, bytes);
  }
}
