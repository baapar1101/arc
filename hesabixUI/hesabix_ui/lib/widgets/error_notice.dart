import 'package:flutter/material.dart';

class ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onClose;

  const ErrorNotice({super.key, required this.message, this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.errorContainer;
    final fg = cs.onErrorContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'error',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.error.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fg, height: 1.3),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                icon: Icon(Icons.close, color: fg),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
              ),
          ],
        ),
      ),
    );
  }
}


