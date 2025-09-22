import 'package:flutter/material.dart';
import 'dart:async';

class SimpleSplashScreen extends StatefulWidget {
  final String? message;
  final bool showLogo;
  final Color? backgroundColor;
  final Color? primaryColor;
  final Duration displayDuration;
  final VoidCallback? onComplete;
  final Locale? locale;

  const SimpleSplashScreen({
    super.key,
    this.message,
    this.showLogo = true,
    this.backgroundColor,
    this.primaryColor,
    this.displayDuration = const Duration(seconds: 4),
    this.onComplete,
    this.locale,
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
    
    // Start display timer
    _displayTimer = Timer(widget.displayDuration, () {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _displayTimer?.cancel();
    super.dispose();
  }

  String _getAppName() {
    if (widget.locale != null && widget.locale!.languageCode == 'fa') {
      return 'حسابیکس';
    }
    return 'Hesabix';
  }


  String _getLoadingMessage() {
    if (widget.locale != null && widget.locale!.languageCode == 'fa') {
      return 'در حال بارگذاری...';
    }
    return 'Loading...';
  }

  String _getVersionInfo() {
    if (widget.locale != null && widget.locale!.languageCode == 'fa') {
      return 'نسخه 1.0.0';
    }
    return 'Version 1.0.0';
  }

  String _getMotto() {
    if (widget.locale != null && widget.locale!.languageCode == 'fa') {
      return 'جهان با تعاون زیبا می‌شود';
    }
    return 'The world becomes beautiful through cooperation';
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
                      _getAppName(),
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
                        _getMotto(),
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
                          widget.message ?? _getLoadingMessage(),
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
                      _getVersionInfo(),
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
