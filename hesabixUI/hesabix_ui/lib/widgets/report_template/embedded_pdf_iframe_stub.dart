import 'dart:typed_data';

import 'package:flutter/material.dart';

/// روی غیروب؛ پیش‌نمایش درون‌صفحه پشتیبانی نمی‌شود.
class ReportTemplateEmbeddedPdf extends StatelessWidget {
  final Uint8List bytes;

  const ReportTemplateEmbeddedPdf({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'برای مشاهدهٔ PDF در دسکتاپ، از دکمهٔ «دانلود PDF» استفاده کنید؛ فایل در پوشهٔ Downloads ذخیره می‌شود.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
