import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Error404Page extends StatelessWidget {
  const Error404Page({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFAFAFA),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F0F0F),
                    const Color(0xFF1A1A2E),
                    const Color(0xFF16213E),
                  ]
                : [
                    const Color(0xFFFAFAFA),
                    const Color(0xFFF1F5F9),
                    const Color(0xFFE2E8F0),
                  ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // آیکون 404 ساده
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: isDark
                            ? [
                                const Color(0xFF6366F1).withValues(alpha: 0.4),
                                const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                const Color(0xFFEC4899).withValues(alpha: 0.1),
                              ]
                            : [
                                const Color(0xFF6366F1).withValues(alpha: 0.3),
                                const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                const Color(0xFFEC4899).withValues(alpha: 0.05),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                              : const Color(0xFF4F46E5).withValues(alpha: 0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '404',
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF6366F1)
                              : const Color(0xFF4F46E5),
                          shadows: [
                            Shadow(
                              color: isDark
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.6)
                                  : const Color(0xFF4F46E5).withValues(alpha: 0.4),
                              blurRadius: 25,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 50),
                  
                  // متن اصلی
                  Column(
                    children: [
                      // عنوان اصلی
                      Text(
                        'صفحه مورد نظر یافت نشد',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                          height: 1.2,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // توضیحات
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'متأسفانه صفحه‌ای که به دنبال آن هستید وجود ندارد یا حذف شده است. لطفاً آدرس را بررسی کنید یا از دکمه زیر استفاده کنید.',
                          style: TextStyle(
                            fontSize: 18,
                            color: isDark 
                                ? Colors.grey[300] 
                                : const Color(0xFF64748B),
                            height: 1.6,
                            letterSpacing: 0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      const SizedBox(height: 60),
                      
                      // دکمه صفحه نخست
                      ElevatedButton.icon(
                        onPressed: () {
                          context.go('/');
                        },
                        icon: const Icon(Icons.home, size: 20),
                        label: const Text('صفحه نخست'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 6,
                          shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}
