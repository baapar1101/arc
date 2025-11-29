import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Dialog راهنمای اتصال بین نودها
class WorkflowConnectionHelpDialog extends StatelessWidget {
  const WorkflowConnectionHelpDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const WorkflowConnectionHelpDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    String localizedText(String faText, String enText) {
      return t.localeName.startsWith('fa') ? faText : enText;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 8),
          Text(localizedText('راهنمای اتصال نودها', 'How to Connect Nodes')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMethodSection(
              context,
              localizedText('روش 1: Drag & Drop (پیشنهادی)', 'Method 1: Drag & Drop (Recommended)'),
              [
                localizedText('1. روی نقطه خروجی (Output) یک نود کلیک کنید و نگه دارید', '1. Click and hold on the output point of a node'),
                localizedText('2. ماوس را بکشید - یک خط موقت نمایش داده می‌شود', '2. Drag your mouse - a temporary line will appear'),
                localizedText('3. ماوس را روی نقطه ورودی (Input) نود دیگر رها کنید', '3. Release on the input point of another node'),
              ],
              Icons.drag_handle,
              Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildMethodSection(
              context,
              localizedText('روش 2: Click & Click', 'Method 2: Click & Click'),
              [
                localizedText('1. روی نقطه خروجی (Output) یک نود کلیک کنید', '1. Click on the output point of a node'),
                localizedText('2. روی نقطه ورودی (Input) نود دیگر کلیک کنید', '2. Click on the input point of another node'),
              ],
              Icons.touch_app,
              Colors.green,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 20, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        localizedText('نکات مهم:', 'Tips:'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localizedText(
                      '• نودهای Trigger فقط نقطه خروجی دارند\n• نودهای Action هم ورودی و هم خروجی دارند\n• برای حذف اتصال: روی آن کلیک کرده و Delete بزنید',
                      '• Trigger nodes only have output points\n• Action nodes have both input and output points\n• To delete connection: click on it and press Delete',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizedText('متوجه شدم', 'Got it')),
        ),
      ],
    );
  }

  Widget _buildMethodSection(
    BuildContext context,
    String title,
    List<String> steps,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

