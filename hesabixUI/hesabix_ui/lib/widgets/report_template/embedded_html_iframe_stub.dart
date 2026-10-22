import 'package:flutter/material.dart';

class ReportTemplateEmbeddedHtml extends StatelessWidget {
  final String html;
  final Map<String, dynamic>? previewMarginsMm;

  const ReportTemplateEmbeddedHtml({
    super.key,
    required this.html,
    this.previewMarginsMm,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('پیش‌نمایش HTML فقط در نسخه وب در دسترس است.'),
    );
  }
}
