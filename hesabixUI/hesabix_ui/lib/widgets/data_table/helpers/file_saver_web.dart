import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

class FileSaver {
  static Future<String?> saveBytes(List<int> bytes, String filename) async {
    await web_utils.saveBytesAsFileWeb(bytes, filename);
    return null;
  }
}


