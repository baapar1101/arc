import 'dart:io';

bool get isProductCameraContextSecure => true;

Future<void> releaseProductCameraFile(String path) async {
  if (path.isEmpty) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // The platform may already have cleaned up the temporary camera file.
  }
}
