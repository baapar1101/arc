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

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 8),
          Text(t.workflowConnectionHelpTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMethodSection(
              context,
              t.workflowConnectionHelpMethod1,
              [
                t.workflowConnectionHelpMethod1Step1,
                t.workflowConnectionHelpMethod1Step2,
                t.workflowConnectionHelpMethod1Step3,
              ],
              Icons.drag_handle,
              Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildMethodSection(
              context,
              t.workflowConnectionHelpMethod2,
              [
                t.workflowConnectionHelpMethod2Step1,
                t.workflowConnectionHelpMethod2Step2,
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
                        t.workflowConnectionHelpTips,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.workflowConnectionHelpTipsText,
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
          child: Text(t.workflowConnectionHelpGotIt),
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

