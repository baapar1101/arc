import 'dart:html' as html;

class FileSaver {
  static Future<String?> saveBytes(List<int> bytes, String filename) async {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
    return null;
  }
}


