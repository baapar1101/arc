import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Error404Page extends StatefulWidget {
  const Error404Page({super.key});

  @override
  State<Error404Page> createState() => _Error404PageState();
}

class _Error404PageState extends State<Error404Page>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    
    // کنترلرهای انیمیشن
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // انیمیشن‌ها
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rotateController,
      curve: Curves.easeInOut,
    ));

    // شروع انیمیشن‌ها
    _startAnimations();
  }

  void _startAnimations() async {
    await _fadeController.forward();
    await _slideController.forward();
    await _bounceController.forward();
    
    // انیمیشن‌های مداوم
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _bounceController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

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
                  // انیمیشن 404 با افکت‌های پیشرفته
                  AnimatedBuilder(
                    animation: Listenable.merge([_bounceAnimation, _pulseAnimation, _rotateAnimation]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _bounceAnimation.value * _pulseAnimation.value,
                        child: Transform.rotate(
                          angle: _rotateAnimation.value * 0.1,
                          child: Container(
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
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // حلقه‌های متحرک
                                ...List.generate(3, (index) {
                                  return AnimatedBuilder(
                                    animation: _rotateAnimation,
                                    builder: (context, child) {
                                      return Transform.rotate(
                                        angle: _rotateAnimation.value * (2 * 3.14159) * (index + 1) * 0.3,
                                        child: Container(
                                          width: 180 - (index * 20),
                                          height: 180 - (index * 20),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isDark
                                                  ? const Color(0xFF6366F1).withValues(alpha: 0.3 - (index * 0.1))
                                                  : const Color(0xFF4F46E5).withValues(alpha: 0.2 - (index * 0.05)),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                                // متن 404
                                Text(
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
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 50),
                  
                  // متن اصلی با انیمیشن
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
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
                              'متأسفانه صفحه‌ای که به دنبال آن هستید وجود ندارد یا حذف شده است. لطفاً آدرس را بررسی کنید یا از دکمه‌های زیر استفاده کنید.',
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
                          
                          // دکمه بازگشت
                          AnimatedBuilder(
                            animation: _fadeAnimation,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, 30 * (1 - _fadeAnimation.value)),
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    // همیشه سعی کن به صفحه قبلی برگردی
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context);
                                    } else {
                                      // اگر نمی‌تونی pop کنی، به root برگرد
                                      context.go('/');
                                    }
                                  },
                                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                                  label: const Text('بازگشت به صفحه قبلی'),
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
                              );
                            },
                          ),
                        ],
                      ),
                    ),
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
