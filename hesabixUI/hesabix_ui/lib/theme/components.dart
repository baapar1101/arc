import 'package:flutter/material.dart';

InputDecorationTheme appInputDecorationTheme(ColorScheme scheme) => InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
      labelStyle: TextStyle(color: scheme.onSurface),
    );

ElevatedButtonThemeData appElevatedButtonTheme(ColorScheme scheme) => ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

AppBarTheme appAppBarTheme(ColorScheme scheme) => AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
    );

const CardThemeData appCardTheme = CardThemeData(clipBehavior: Clip.antiAlias);


