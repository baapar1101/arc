import 'package:flutter/material.dart';

/// نوار قدرت رمز عبور — real-time feedback.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  final int minLength;

  const PasswordStrengthMeter({
    super.key,
    required this.password,
    this.minLength = 8,
  });

  int get _score {
    if (password.isEmpty) return 0;
    var s = 0;
    if (password.length >= minLength) s++;
    if (password.length >= minLength + 4) s++;
    if (RegExp(r'[A-Za-z]').hasMatch(password) && RegExp(r'\d').hasMatch(password)) s++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) s++;
    return s.clamp(0, 4);
  }

  (Color, String) _level(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_score) {
      case 0:
        return (scheme.outline, '');
      case 1:
        return (scheme.error, 'ضعیف');
      case 2:
        return (const Color(0xFFE65100), 'متوسط');
      case 3:
        return (const Color(0xFFF9A825), 'خوب');
      default:
        return (const Color(0xFF2E7D32), 'قوی');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final (color, label) = _level(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _score / 4,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}
