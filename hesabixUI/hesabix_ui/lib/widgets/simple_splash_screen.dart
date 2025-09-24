import 'package:flutter/material.dart';
import 'dart:async';
import '../core/auth_store.dart';
import '../l10n/app_localizations.dart';

class SimpleSplashScreen extends StatefulWidget {
  final String? message;
  final bool showLogo;
  final Color? backgroundColor;
  final Color? primaryColor;
  final Duration displayDuration;
  final VoidCallback? onComplete;
  final Locale? locale;
  final AuthStore? authStore;

  const SimpleSplashScreen({
    super.key,
    this.message,
    this.showLogo = true,
    this.backgroundColor,
    this.primaryColor,
    this.displayDuration = const Duration(seconds: 1),
    this.onComplete,
    this.locale,
    this.authStore,
  });

  @override
  State<SimpleSplashScreen> createState() => _SimpleSplashScreenState();
}

class _SimpleSplashScreenState extends State<SimpleSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  Timer? _displayTimer;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    // Start animations
    _fadeController.forward();
    _scaleController.forward();
    
    // Start display timer with authentication check
    _displayTimer = Timer(widget.displayDuration, () {
      _checkAuthenticationAndComplete();
    });
  }

  void _checkAuthenticationAndComplete() {
    print('🔍 SPLASH DEBUG: Checking authentication and completing splash screen');
    
    // اگر authStore موجود است، وضعیت احراز هویت را بررسی کن
    if (widget.authStore != null) {
      final hasApiKey = widget.authStore!.apiKey != null && widget.authStore!.apiKey!.isNotEmpty;
      print('🔍 SPLASH DEBUG: AuthStore available, has API key: $hasApiKey');
      
      // اگر کاربر وارد شده، URL فعلی را ذخیره کن
      if (hasApiKey) {
        // URL فعلی را از window.location بگیر
        try {
          // در web، URL فعلی را از window.location می‌گیریم
          final currentUrl = Uri.base.path;
          print('🔍 SPLASH DEBUG: Current URL from Uri.base: $currentUrl');
          
          if (currentUrl.isNotEmpty && 
              currentUrl != '/' && 
              currentUrl != '/login' &&
              (currentUrl.startsWith('/user/profile/') || currentUrl.startsWith('/business/'))) {
            print('🔍 SPLASH DEBUG: Saving current URL: $currentUrl');
            widget.authStore!.saveLastUrl(currentUrl);
          }
        } catch (e) {
          print('🔍 SPLASH DEBUG: Error getting current URL: $e');
        }
      }
      
      // اگر کاربر وارد نشده، به صفحه لاگین هدایت می‌شود
      // اگر کاربر وارد شده، در صفحه کنونی می‌ماند
      // این منطق در main.dart در GoRouter redirect مدیریت می‌شود
    } else {
      print('🔍 SPLASH DEBUG: AuthStore is null');
    }
    
    print('🔍 SPLASH DEBUG: Calling onComplete callback');
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _displayTimer?.cancel();
    super.dispose();
  }

  String _getAppName(BuildContext context) {
    final t = AppLocalizations.of(context);
    return t.appTitle;
  }


  String _getLoadingMessage(BuildContext context) {
    final t = AppLocalizations.of(context);
    return t.loading;
  }

  String _getVersionInfo(BuildContext context) {
    final t = AppLocalizations.of(context);
    return t.version;
  }

  String _getMotto(BuildContext context) {
    final t = AppLocalizations.of(context);
    return t.motto;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final bgColor = widget.backgroundColor ?? colorScheme.surface;
    final primary = widget.primaryColor ?? colorScheme.primary;
    
    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark 
              ? [
                  bgColor,
                  bgColor.withValues(alpha: 0.95),
                ]
              : [
                  bgColor,
                  bgColor.withValues(alpha: 0.98),
                ],
          ),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([_fadeAnimation, _scaleAnimation]),
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo Section - Simple and Clean
                    if (widget.showLogo) ...[
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            isDark ? 'assets/images/logo-light.png' : 'assets/images/logo-blue.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.account_balance,
                                  size: 50,
                                  color: colorScheme.onPrimary,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    
                    // App Name - Simple and Clean
                    Text(
                      _getAppName(context),
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Motto/Slogan - Simple Design
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _getMotto(context),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 48),
                    
                    // Loading Section - Simple and Clean
                    Column(
                      children: [
                        // Simple Loading Indicator
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(primary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Simple Loading Message
                        Text(
                          widget.message ?? _getLoadingMessage(context),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 60),
                    
                    // Simple Version Info
                    Text(
                      _getVersionInfo(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
