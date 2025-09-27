import 'dart:io';

class FileSaver {
  static Future<String?> saveBytes(List<int> bytes, String filename) async {
    final homeDir = Platform.environment['HOME'] ?? Directory.current.path;
    final downloadsDir = Directory('$homeDir/Downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final file = File('${downloadsDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}


