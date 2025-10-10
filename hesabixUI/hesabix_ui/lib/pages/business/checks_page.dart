import 'package:flutter/material.dart';
import '../../core/auth_store.dart';

class ChecksPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const ChecksPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}


