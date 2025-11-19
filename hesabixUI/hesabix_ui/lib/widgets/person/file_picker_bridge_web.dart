import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

class PickedFileData {
  final String name;
  final List<int> bytes;
  PickedFileData(this.name, this.bytes);
}

class FilePickerBridge {
  static Future<PickedFileData?> pickExcel() async {
    try {
      final input = html.FileUploadInputElement()
        ..accept = '.xlsx'
        ..multiple = false;
      
      input.click();
      
      final completer = Completer<PickedFileData?>();
      
      input.onChange.listen((e) {
        final files = input.files;
        if (files != null && files.isNotEmpty) {
          final file = files.first;
          final reader = html.FileReader();
          
          reader.onLoad.listen((e) {
            final bytes = reader.result as Uint8List;
            completer.complete(PickedFileData(file.name, bytes.toList()));
          });
          
          reader.onError.listen((e) {
            completer.complete(null);
          });
          
          reader.readAsArrayBuffer(file);
        } else {
          completer.complete(null);
        }
      });
      
      return await completer.future;
    } catch (e) {
      return null;
    }
  }
}


