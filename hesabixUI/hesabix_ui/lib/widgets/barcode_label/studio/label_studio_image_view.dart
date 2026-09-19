import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/barcode_label/label_design_v1.dart';
import '../render/label_image_resolver.dart';

/// نمایش تصویر المان در استودیو (همه پلتفرم‌ها).
class LabelStudioImageView extends StatelessWidget {
  final LabelElement element;
  final int? businessId;
  final Map<String, dynamic> context;

  const LabelStudioImageView({
    super.key,
    required this.element,
    this.businessId,
    this.context = const {},
  });

  @override
  Widget build(BuildContext ctx) {
    return FutureBuilder<Uint8List?>(
      future: LabelImageResolver.resolveElement(
        element,
        context: context,
        businessId: businessId,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return ColoredBox(
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
          );
        }
        final fit = switch (element.props['fit']?.toString()) {
          'cover' => BoxFit.cover,
          'fill' => BoxFit.fill,
          _ => BoxFit.contain,
        };
        final opacity = (element.props['opacity'] as num?)?.toDouble() ?? 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: ColoredBox(
            color: Colors.white,
            child: Image.memory(bytes, fit: fit, gaplessPlayback: true),
          ),
        );
      },
    );
  }
}
