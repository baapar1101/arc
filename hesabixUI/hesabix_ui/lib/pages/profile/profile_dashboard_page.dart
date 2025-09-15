import 'package:flutter/material.dart';

class ProfileDashboardPage extends StatelessWidget {
  const ProfileDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('User Profile Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          Text('Summary and quick actions will appear here.'),
        ],
      ),
    );
  }
}


