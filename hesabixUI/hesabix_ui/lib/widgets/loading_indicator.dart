import 'package:flutter/material.dart';

/// یک widget ساده برای نمایش loading indicator
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}




