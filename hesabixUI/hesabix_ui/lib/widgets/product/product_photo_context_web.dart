import 'package:web/web.dart' as web;

bool get isProductCameraContextSecure => web.window.isSecureContext;

Future<void> releaseProductCameraFile(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}
