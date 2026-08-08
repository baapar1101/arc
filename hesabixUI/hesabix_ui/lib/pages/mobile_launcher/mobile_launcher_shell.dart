import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/error_extractor.dart';

/// بارگذاری زمینهٔ دسترسی کسب‌وکار برای مسیرهای داخل `/mobile-launcher/...`
/// تا `hasBusinessPermission` مثل پنل اصلی درست عمل کند.
class MobileLauncherShell extends StatefulWidget {
  const MobileLauncherShell({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.child,
  });

  final int businessId;
  final AuthStore authStore;
  final Widget child;

  @override
  State<MobileLauncherShell> createState() => _MobileLauncherShellState();
}

class _MobileLauncherShellState extends State<MobileLauncherShell> {
  late Future<_MobileLauncherBootstrap> _bootstrap;
  final _service = BusinessDashboardService(ApiClient());

  @override
  void initState() {
    super.initState();
    _bootstrap = _runBootstrap();
  }

  @override
  void didUpdateWidget(covariant MobileLauncherShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.authStore != widget.authStore) {
      _bootstrap = _runBootstrap();
    }
  }

  Future<_MobileLauncherBootstrap> _runBootstrap() async {
    final ok = await _service.hasBusinessAccess(widget.businessId);
    if (!ok) {
      return _MobileLauncherBootstrap.deniedAccess();
    }
    try {
      if (widget.authStore.currentBusiness?.id != widget.businessId) {
        final data = await _service.getBusinessWithPermissions(widget.businessId);
        await widget.authStore.setCurrentBusiness(data);
      }
      return _MobileLauncherBootstrap.ready();
    } catch (e) {
      return _MobileLauncherBootstrap.error(e);
    }
  }

  void _leaveLauncherShell() {
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    router.go('/user/profile/businesses');
  }

  Widget _guardBack(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!context.mounted) return;
        _leaveLauncherShell();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MobileLauncherBootstrap>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _guardBack(
            const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        }
        final r = snap.data ?? _MobileLauncherBootstrap.deniedAccess();
        if (r.needsRedirectNoAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!context.mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            final l10n = AppLocalizations.of(context);
            final router = GoRouter.of(context);
            await MobileLauncherPrefs.clearResumeLauncher(
              widget.authStore.currentUserId,
            );
            if (!context.mounted) return;
            messenger?.showSnackBar(
              SnackBar(content: Text(l10n.mobileLauncherBusinessNoAccess)),
            );
            router.go('/user/profile/businesses');
          });
          return _guardBack(const Scaffold(body: SizedBox.shrink()));
        }
        final loadErr = r.loadError;
        if (loadErr != null) {
          final t = AppLocalizations.of(context);
          final msg = ErrorExtractor.extractErrorMessage(loadErr, t);
          return _guardBack(
            Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(msg, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() {
                            _bootstrap = _runBootstrap();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(t.retry),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _leaveLauncherShell,
                        child: Text(t.mobileLauncherBackToAccount),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        // خانهٔ لانچر خودش PopScope دارد؛ اینجا child را بدون قفل اضافه پاس می‌دهیم.
        return widget.child;
      },
    );
  }
}

class _MobileLauncherBootstrap {
  _MobileLauncherBootstrap._({this.needsRedirectNoAccess = false, this.loadError});

  final bool needsRedirectNoAccess;
  final Object? loadError;

  factory _MobileLauncherBootstrap.ready() =>
      _MobileLauncherBootstrap._(needsRedirectNoAccess: false);

  factory _MobileLauncherBootstrap.deniedAccess() =>
      _MobileLauncherBootstrap._(needsRedirectNoAccess: true);

  factory _MobileLauncherBootstrap.error(Object e) =>
      _MobileLauncherBootstrap._(needsRedirectNoAccess: false, loadError: e);
}
