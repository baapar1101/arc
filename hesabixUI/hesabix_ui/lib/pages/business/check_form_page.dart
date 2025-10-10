import 'package:flutter/material.dart';
import '../../core/auth_store.dart';

class CheckFormPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;
  final int? checkId; // null => new, not null => edit

  const CheckFormPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.checkId,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}


