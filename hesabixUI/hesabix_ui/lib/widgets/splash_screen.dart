import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SplashScreen extends StatelessWidget {
  final String? message;
  final bool showLogo;
  final Color? backgroundColor;
  final Color? primaryColor;

  const SplashScreen({
    super.key,
    this.message,
    this.showLogo = true,
    this.backgroundColor,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final bgColor = backgroundColor ?? colorScheme.surface;
    final primary = primaryColor ?? colorScheme.primary;
    
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Section
            if (showLogo) ...[
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
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
                          size: 60,
                          color: colorScheme.onPrimary,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
            
            // App Name
            Text(
              'Hesabix',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            
            // Subtitle
            Text(
              AppLocalizations.of(context).businessManagementPlatform,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 48),
            
            // Loading Indicator
            Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Loading Message
                Text(
                  message ?? AppLocalizations.of(context).loading,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 80),
            
            // Version Info (Optional)
            Text(
              'Version 1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Animated Splash Screen with fade effects
class AnimatedSplashScreen extends StatefulWidget {
  final String? message;
  final bool showLogo;
  final Color? backgroundColor;
  final Color? primaryColor;
  final Duration animationDuration;
  final Duration minimumDisplayDuration;

  const AnimatedSplashScreen({
    super.key,
    this.message,
    this.showLogo = true,
    this.backgroundColor,
    this.primaryColor,
    this.animationDuration = const Duration(milliseconds: 1500),
    this.minimumDisplayDuration = const Duration(seconds: 2),
  });

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fadeAnimation, _scaleAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: SplashScreen(
              message: widget.message,
              showLogo: widget.showLogo,
              backgroundColor: widget.backgroundColor,
              primaryColor: widget.primaryColor,
            ),
          ),
        );
      },
    );
  }
}
