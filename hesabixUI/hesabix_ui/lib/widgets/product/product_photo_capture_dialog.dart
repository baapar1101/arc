import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'product_photo_context_stub.dart'
    if (dart.library.js_interop) 'product_photo_context_web.dart';

typedef CapturedProductPhoto = ({Uint8List bytes, String filename});

enum _CameraProblem {
  secureContext,
  permission,
  noDevice,
  unavailable,
  capture,
}

class ProductPhotoCaptureDialog extends StatefulWidget {
  const ProductPhotoCaptureDialog({super.key});

  @override
  State<ProductPhotoCaptureDialog> createState() =>
      _ProductPhotoCaptureDialogState();
}

class _ProductPhotoCaptureDialogState extends State<ProductPhotoCaptureDialog>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void> _released = Future.value();
  CapturedProductPhoto? _photo;
  _CameraProblem? _problem;
  int _attempt = 0;
  bool _capturing = false;
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attempt++;
    unawaited(_releaseCamera());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_photo != null || _problem != null) return;
    if (state == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      unawaited(_openCamera());
      return;
    }
    // Permission dialogs can make the app inactive before initialization.
    final shouldSuspend =
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive &&
            _camera?.value.isInitialized == true);
    if (shouldSuspend && !_suspended) {
      _suspended = true;
      _attempt++;
      unawaited(_releaseCamera());
      setState(() => _capturing = false);
    }
  }

  bool _isCurrent(int attempt) => mounted && attempt == _attempt;

  Future<void> _openCamera() async {
    final attempt = ++_attempt;
    setState(() {
      _photo = null;
      _problem = null;
    });
    if (!isProductCameraContextSecure) {
      _showProblem(_CameraProblem.secureContext);
      return;
    }
    if (!kIsWeb &&
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform)) {
      _showProblem(_CameraProblem.unavailable);
      return;
    }

    await _released;
    if (!_isCurrent(attempt)) return;
    try {
      final cameras = await availableCameras();
      if (!_isCurrent(attempt)) return;
      if (cameras.isEmpty) {
        _showProblem(_CameraProblem.noDevice);
        return;
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _camera = controller;
      await controller.initialize();
      if (!_isCurrent(attempt)) return;
      if (controller.value.hasError) {
        _showProblem(_CameraProblem.unavailable);
        return;
      }
      controller.addListener(_onCameraError);
      setState(() {});
    } catch (error) {
      if (_isCurrent(attempt)) {
        _showProblem(_problemFor(error, _CameraProblem.unavailable));
      }
    }
  }

  void _onCameraError() {
    if (_camera?.value.hasError == true) {
      _showProblem(_CameraProblem.unavailable);
    }
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturing) return;
    final attempt = _attempt;
    setState(() => _capturing = true);
    try {
      final file = await camera.takePicture();
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } finally {
        unawaited(releaseProductCameraFile(file.path));
      }
      if (!_isCurrent(attempt)) return;
      unawaited(_releaseCamera());
      // Decode a small frame to detect an unusable capture before offering to use it.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!_isCurrent(attempt)) return;
      setState(() {
        _capturing = false;
        // camera_web returns a JPEG object URL without an image filename.
        _photo = (
          bytes: bytes,
          filename: kIsWeb ? 'product-photo.jpg' : file.name,
        );
      });
    } catch (error) {
      if (_isCurrent(attempt)) {
        _showProblem(_problemFor(error, _CameraProblem.capture));
      }
    }
  }

  void _showProblem(_CameraProblem problem) {
    _attempt++;
    unawaited(_releaseCamera());
    setState(() {
      _problem = problem;
      _capturing = false;
    });
  }

  Future<void> _releaseCamera() {
    final camera = _camera;
    if (camera != null) {
      _camera = null;
      camera.removeListener(_onCameraError);
      _released = _disposeCamera(camera);
    }
    return _released;
  }

  Future<void> _disposeCamera(CameraController camera) async {
    try {
      await camera.dispose();
    } catch (error) {
      debugPrint('Could not close product camera: $error');
    }
  }

  _CameraProblem _problemFor(Object error, _CameraProblem fallback) {
    if (error is! CameraException) return fallback;
    return switch (error.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' ||
      'CameraAccessRestricted' ||
      'permissionDenied' ||
      'cameraPermission' ||
      'accessDenied' => _CameraProblem.permission,
      'cameraNotFound' ||
      'noSuchCamera' ||
      'notFound' => _CameraProblem.noDevice,
      _ => fallback,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final photo = _photo;
    final camera = _camera;
    final problem = _problem;
    final ready = camera?.value.isInitialized == true;
    return AlertDialog(
      title: Text(t.productPhoto),
      content: SizedBox(
        width: 480,
        height: math.min(380, MediaQuery.sizeOf(context).height * 0.50),
        child: Center(
          child: switch (problem) {
            _CameraProblem.secureContext => Text(
              t.productPhotoCameraSecureContext,
            ),
            _CameraProblem.permission => Text(t.productPhotoCameraPermission),
            _CameraProblem.noDevice => Text(t.productPhotoNoCamera),
            _CameraProblem.unavailable => Text(t.productPhotoCameraUnavailable),
            _CameraProblem.capture => Text(t.productPhotoCaptureFailed),
            null =>
              photo != null
                  ? Image.memory(photo.bytes, fit: BoxFit.contain)
                  : (ready
                        ? CameraPreview(camera!)
                        : const CircularProgressIndicator()),
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        if (photo != null) ...[
          TextButton(onPressed: _openCamera, child: Text(t.productPhotoRetake)),
          FilledButton(
            onPressed: () => Navigator.pop(context, photo),
            child: Text(t.productPhotoUse),
          ),
        ] else if (problem != null && problem != _CameraProblem.secureContext)
          OutlinedButton(onPressed: _openCamera, child: Text(t.retry))
        else if (problem == null)
          FilledButton.icon(
            onPressed: ready && !_capturing ? _takePhoto : null,
            icon: const Icon(Icons.photo_camera),
            label: Text(t.productPhotoTake),
          ),
      ],
    );
  }
}
