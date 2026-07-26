import 'package:flutter/material.dart';

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onPrimary;

    final child = loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        : icon != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(color: foreground)),
                ],
              )
            : Text(label, style: TextStyle(color: foreground));

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        // Keep enabled styling while loading so label/spinner stay onPrimary.
        onPressed: loading ? () {} : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: scheme.primary,
          foregroundColor: foreground,
          disabledBackgroundColor: scheme.primary,
          disabledForegroundColor: foreground,
          textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
        ),
        child: child,
      ),
    );
  }
}
