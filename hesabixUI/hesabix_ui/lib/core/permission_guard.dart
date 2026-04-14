import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_store.dart';

class PermissionGuard {
  static bool checkSuperAdminAccess(AuthStore authStore) {
    return authStore.isSuperAdmin;
  }

  static bool checkAppPermission(AuthStore authStore, String permission) {
    return authStore.hasAppPermission(permission);
  }

  static Widget buildAccessDeniedPage() {
    return Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('دسترسی غیرمجاز'),
          backgroundColor: Colors.red[50],
          foregroundColor: Colors.red[800],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.block,
                  size: 80,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'دسترسی غیرمجاز',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[800],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'شما دسترسی لازم برای مشاهده این صفحه را ندارید.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => context.go('/user/profile/dashboard'),
                  icon: const Icon(Icons.home),
                  label: const Text('بازگشت به داشبورد'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
