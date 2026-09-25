import 'package:flutter/material.dart';

/// دیالوگ گرامیداشت توسعه‌دهندگان فقید پروژهٔ حسابیکس (میانبر مخفی Q+J+A+M).
class HesabixDevelopersMemorialDialog extends StatelessWidget {
  const HesabixDevelopersMemorialDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 40,
                color: theme.colorScheme.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 16),
              Text(
                'یاد و گرامیداشت',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'به یاد توسعه‌دهندگان پروژهٔ حسابیکس',
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'بزرگداشت یاد و خاطرهٔ محمد رضایی جم و مصطفی شادمان، '
                'از توسعه‌دهندگان پروژهٔ حسابیکس، '
                'که تلاش‌ها و دستاوردهایشان همواره در این مسیر ماندگار است.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('باشد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
