import 'package:flutter/material.dart';

class AppColorTokens {
  static ColorScheme schemeFromSeed(Color seed, {required bool dark}) {
    if (dark) {
      return ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F172A),
      ).copyWith(
        primary: seed,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFF1E40AF),
        onPrimaryContainer: const Color(0xFFEFF6FF),
        secondary: const Color(0xFF60A5FA),
        onSecondary: const Color(0xFF08111F),
        secondaryContainer: const Color(0xFF172554),
        onSecondaryContainer: const Color(0xFFDBEAFE),
        surface: const Color(0xCC0F172A),
        surfaceContainerLowest: const Color(0x000A0F1D),
        surfaceContainerLow: const Color(0x99111827),
        surfaceContainer: const Color(0xB3111827),
        surfaceContainerHigh: const Color(0xCC172033),
        surfaceContainerHighest: const Color(0xD91E293B),
        onSurface: const Color(0xFFF8FAFC),
        onSurfaceVariant: const Color(0xFFCBD5E1),
        outline: const Color(0xFF64748B),
        outlineVariant: const Color(0xFF334155),
        inverseSurface: const Color(0xFFF8FAFC),
        onInverseSurface: const Color(0xFF0F172A),
        inversePrimary: const Color(0xFF93C5FD),
      );
    }

    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFF8FAFF),
    ).copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDBEAFE),
      onPrimaryContainer: const Color(0xFF172554),
      secondary: const Color(0xFF2563EB),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE0ECFF),
      onSecondaryContainer: const Color(0xFF172554),
      surface: const Color(0xDDF8FAFF),
      surfaceContainerLowest: const Color(0x00FFFFFF),
      surfaceContainerLow: const Color(0xCCFFFFFF),
      surfaceContainer: const Color(0xDDFFFFFF),
      surfaceContainerHigh: const Color(0xE6F8FAFF),
      surfaceContainerHighest: const Color(0xFFF0F5FF),
      onSurface: const Color(0xFF0F172A),
      onSurfaceVariant: const Color(0xFF475569),
      outline: const Color(0xFF94A3B8),
      outlineVariant: const Color(0xFFCBD5E1),
      inverseSurface: const Color(0xFF0F172A),
      onInverseSurface: const Color(0xFFF8FAFC),
      inversePrimary: const Color(0xFF60A5FA),
    );
  }
}
