import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_store.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
          title: Text('دسترسی غیرمجاز'),
          backgroundColor: SemanticColorResolver.negative(context).withValues(alpha: 0.12),
          foregroundColor: SemanticColorResolver.negative(context),
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
                  color: SemanticColorResolver.negative(context),
                ),
                SizedBox(height: 24),
                Text(
                  'دسترسی غیرمجاز',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: SemanticColorResolver.negative(context),
                  ),
                ),
                SizedBox(height: 16),
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
                  icon: Icon(Icons.home),
                  label: const Text('بازگشت به داشبورد'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SemanticColorResolver.negative(context),
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
