import 'package:flutter/material.dart';

InputDecorationTheme appInputDecorationTheme(ColorScheme scheme) {
  const radius = BorderRadius.all(Radius.circular(4));
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: radius, borderSide: side);

  final enabled = outline(BorderSide(color: scheme.outline, width: 1));
  final focused = outline(BorderSide(color: scheme.primary, width: 2));
  final disabled = outline(
    BorderSide(color: scheme.onSurface.withValues(alpha: 0.12), width: 1),
  );
  final error = outline(BorderSide(color: scheme.error, width: 1));
  final focusedError = outline(BorderSide(color: scheme.error, width: 2));

  return InputDecorationTheme(
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: focused,
    disabledBorder: disabled,
    errorBorder: error,
    focusedErrorBorder: focusedError,
    filled: true,
    fillColor: scheme.surfaceContainerHighest,
    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
    labelStyle: TextStyle(color: scheme.onSurface),
  );
}

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


