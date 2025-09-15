import 'package:flutter/material.dart';

class AppColorTokens {
  static ColorScheme schemeFromSeed(Color seed, {required bool dark}) {
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
  }
}


