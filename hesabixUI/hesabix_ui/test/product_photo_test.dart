import 'dart:async';
import 'dart:convert';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/controllers/product_form_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/product_form_data.dart';
import 'package:hesabix_ui/widgets/product/product_photo_capture_dialog.dart';
import 'package:hesabix_ui/widgets/product/sections/product_basic_info_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGNkYPjPwMDAxAAGAAsfAQMU4wsAAAAAAElFTkSuQmCC',
);

void main() {
  late CameraPlatform originalCamera;
  late _TestCamera camera;
  late ProductFormController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalCamera = CameraPlatform.instance;
    CameraPlatform.instance = camera = _TestCamera();
    FilePicker.platform = _TestPicker();
    controller = ProductFormController(businessId: 1)
      ..updateFormData(ProductFormData(imageFileId: 'previous-file'));
  });

  tearDown(() {
    controller.dispose();
    CameraPlatform.instance = originalCamera;
  });

  Future<void> showForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => ProductBasicInfoSection(
                businessId: 1,
                formData: controller.formData,
                onChanged: controller.updateFormData,
                controller: controller,
                categories: const [],
                attributes: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final button = find.text(label).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester) async {
    final shutter = find.descendant(
      of: find.byType(ProductPhotoCaptureDialog),
      matching: find.text('Take photo'),
    );
    await tester.tap(shutter);
    final usePhoto = find.text('Use photo');
    for (
      var attempt = 0;
      attempt < 100 && usePhoto.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(usePhoto, findsOneWidget);
    expect(camera.active, isEmpty);
  }

  testWidgets(
    'file selection and confirmed retake use the same pending product image',
    (tester) async {
      await showForm(tester);
      expect(camera.enumerations, 0);
      await tap(tester, 'Choose file');
      await tester.pumpAndSettle();
      expect(controller.selectedImageFilename, 'from-file.png');
      expect(camera.enumerations, 0);

      await tap(tester, 'Take photo');
      await tester.pumpAndSettle();
      expect(camera.active, hasLength(1));
      await capture(tester);
      expect(controller.selectedImageFilename, 'from-file.png');
      await tap(tester, 'Retake photo');
      await tester.pumpAndSettle();
      await capture(tester);
      await tap(tester, 'Use photo');
      await tester.pumpAndSettle();
      expect(controller.selectedImageFilename, 'capture-2.png');
      expect(controller.selectedImageBytes, _png);
      expect(controller.formData.imageFileId, 'previous-file');
      expect(camera.active, isEmpty);
      expect(camera.audioRequested, isFalse);
    },
  );

  testWidgets(
    'cancel from the live camera or photo preview preserves the existing image',
    (tester) async {
      await showForm(tester);
      for (final takePhoto in [false, true]) {
        await tap(tester, 'Take photo');
        await tester.pumpAndSettle();
        if (takePhoto) await capture(tester);
        await tap(tester, 'Cancel');
        await tester.pumpAndSettle();
        expect(controller.selectedImageBytes, isNull);
        expect(controller.formData.imageFileId, 'previous-file');
        expect(camera.active, isEmpty);
      }
    },
  );

  testWidgets(
    'permission, absent device, busy camera and failed capture preserve file selection',
    (tester) async {
      await showForm(tester);
      for (final (error, expected) in [
        (
          CameraException('CameraAccessDenied', 'test'),
          'Camera access was denied',
        ),
        (null, 'No camera was found'),
        (
          CameraException('cameraNotReadable', 'test'),
          'The camera is unavailable',
        ),
      ]) {
        camera.enumerationError = error;
        camera.hasDevice = false;
        await tap(tester, 'Take photo');
        await tester.pumpAndSettle();
        expect(find.textContaining(expected), findsOneWidget);
        await tap(tester, 'Cancel');
        await tester.pumpAndSettle();
        expect(controller.formData.imageFileId, 'previous-file');
        expect(camera.active, isEmpty);
      }

      camera.enumerationError = null;
      camera.hasDevice = true;
      camera.failCapture = true;
      await tap(tester, 'Take photo');
      await tester.pumpAndSettle();
      await tap(tester, 'Take photo');
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not take a photo'), findsOneWidget);
      expect(camera.active, isEmpty);
      await tap(tester, 'Cancel');
      await tester.pumpAndSettle();
      await tap(tester, 'Choose file');
      await tester.pumpAndSettle();
      expect(controller.selectedImageFilename, 'from-file.png');
    },
  );

  testWidgets(
    'leaving while the camera is opening disposes it when initialization returns',
    (tester) async {
      await showForm(tester);
      final initialization = camera.initialization = Completer<void>();
      await tap(tester, 'Take photo');
      await tester.pump();
      expect(camera.active, hasLength(1));
      await tap(tester, 'Cancel');
      await tester.pumpAndSettle();
      initialization.complete();
      await tester.pumpAndSettle();
      expect(camera.active, isEmpty);
      expect(controller.selectedImageBytes, isNull);
      expect(find.byType(ProductPhotoCaptureDialog), findsNothing);
    },
  );
}

class _TestCamera extends CameraPlatform {
  final active = <int>{};
  int enumerations = 0;
  int _nextId = 0;
  int _taken = 0;
  bool audioRequested = false;
  bool hasDevice = true;
  bool failCapture = false;
  CameraException? enumerationError;
  Completer<void>? initialization;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    enumerations++;
    if (enumerationError case final error?) throw error;
    return [
      if (hasDevice)
        const CameraDescription(
          name: 'test webcam',
          lensDirection: CameraLensDirection.external,
          sensorOrientation: 0,
        ),
    ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    audioRequested = audioRequested || settings.enableAudio;
    final id = ++_nextId;
    active.add(id);
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initialization?.future;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.blue);

  @override
  Future<XFile> takePicture(int cameraId) async {
    if (failCapture) throw CameraException('captureFailed', 'test');
    return _TestPhoto('capture-${++_taken}.png');
  }

  @override
  Future<void> dispose(int cameraId) async {
    active.remove(cameraId);
  }
}

class _TestPhoto extends XFile {
  _TestPhoto(this.name) : super.fromData(_png);

  @override
  final String name;
}

class _TestPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.image);
    expect(withData, isTrue);
    return FilePickerResult([
      PlatformFile(name: 'from-file.png', size: _png.length, bytes: _png),
    ]);
  }
}
