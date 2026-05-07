import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/snackbar_helper.dart';

/// صفحهٔ لانچر سبک (خارج از پنل کسب‌وکار) برای موبایل و POS.
class MobileLauncherPage extends StatefulWidget {
  const MobileLauncherPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  final int businessId;
  final AuthStore authStore;

  @override
  State<MobileLauncherPage> createState() => _MobileLauncherPageState();
}

class _MobileLauncherPageState extends State<MobileLauncherPage> {
  late Future<int> _bgArgb = MobileLauncherPrefs.backgroundColorArgb(
    widget.authStore.currentUserId,
  );

  DateTime? _lastBackPressAt;

  void _reloadBackground() {
    setState(() {
      _bgArgb = MobileLauncherPrefs.backgroundColorArgb(
        widget.authStore.currentUserId,
      );
    });
  }

  bool _isLight(Color c) => c.computeLuminance() > 0.55;

  void _applySystemOverlay(Color bg) {
    if (kIsWeb) return;
    final lightBg = _isLight(bg);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: lightBg ? Brightness.dark : Brightness.light,
        statusBarBrightness: lightBg ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bg.withValues(alpha: 0.94),
        systemNavigationBarIconBrightness:
            lightBg ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Future<void> _validateBusinessAccess() async {
    final api = ApiClient();
    final ok =
        await BusinessDashboardService(api).hasBusinessAccess(widget.businessId);
    if (!mounted) return;
    if (ok) return;
    await MobileLauncherPrefs.clearResumeLauncher(widget.authStore.currentUserId);
    SnackBarHelper.showError(
      context,
      message: AppLocalizations.of(context).mobileLauncherBusinessNoAccess,
    );
    context.go('/user/profile/businesses');
  }

  Future<void> _disableLauncherHome(AppLocalizations t) async {
    await MobileLauncherPrefs.clearResumeLauncher(widget.authStore.currentUserId);
    if (!mounted) return;
    SnackBarHelper.show(context, message: t.mobileLauncherDisableHomeLauncherDone);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _validateBusinessAccess());
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle());
    }
    super.dispose();
  }

  Future<void> _onLauncherWillPop(AppLocalizations t) async {
    if (kIsWeb) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final now = DateTime.now();
    const windowMs = 2200;
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!).inMilliseconds < windowMs) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(t.mobileLauncherExitAppHint),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return PopScope(
      canPop: kIsWeb,
      onPopInvoked: (didPop) async {
        if (didPop || kIsWeb) return;
        await _onLauncherWillPop(t);
      },
      child: FutureBuilder<int>(
        future: _bgArgb,
        builder: (context, snap) {
          final argb = snap.data ?? MobileLauncherPrefs.defaultBackgroundArgb;
          final bg = Color(argb);
          final onBg = _isLight(bg) ? Colors.black87 : Colors.white;
          final cardBg = _isLight(bg)
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.25);

          if (snap.connectionState == ConnectionState.done) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySystemOverlay(bg);
            });
          }

          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: onBg,
              elevation: 0,
              title: Text(
                t.mobileLauncherTitle,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: t.mobileLauncherBackToAccount,
                  icon: Icon(Icons.person_outline, color: onBg),
                  onPressed: () =>
                      context.go('/user/profile/dashboard'),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: onBg),
                  onSelected: (v) async {
                    if (v == 'disable_home') {
                      await _disableLauncherHome(t);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'disable_home',
                      child: Text(t.mobileLauncherDisableHomeLauncherMenu),
                    ),
                  ],
                ),
              ],
            ),
            body: DecoratedBox(
              decoration: BoxDecoration(color: bg),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                    children: [
                      _LauncherTile(
                        icon: Icons.palette_outlined,
                        label: t.mobileLauncherAppearanceTile,
                        bg: cardBg,
                        fg: onBg,
                        onTap: () async {
                          await context.push<void>(
                            '/mobile-launcher/${widget.businessId}/appearance',
                          );
                          _reloadBackground();
                        },
                      ),
                      _LauncherTile(
                        icon: Icons.dashboard_customize_outlined,
                        label: t.mobileLauncherOpenFullPanel,
                        bg: cardBg,
                        fg: onBg,
                        onTap: () => context.go(
                          '/business/${widget.businessId}/dashboard',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LauncherTile extends StatelessWidget {
  const _LauncherTile({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: fg),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
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
