import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MobileLauncherBootstrap>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final r = snap.data ?? _MobileLauncherBootstrap.deniedAccess();
        if (r.needsRedirectNoAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!context.mounted) return;
            await MobileLauncherPrefs.clearResumeLauncher(widget.authStore.currentUserId);
            SnackBarHelper.showError(
              context,
              message: AppLocalizations.of(context).mobileLauncherBusinessNoAccess,
            );
            context.go('/user/profile/businesses');
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final loadErr = r.loadError;
        if (loadErr != null) {
          final t = AppLocalizations.of(context);
          final msg = ErrorExtractor.extractErrorMessage(loadErr, t);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              SnackBarHelper.showError(context, message: msg);
            }
          });
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(msg, textAlign: TextAlign.center),
              ),
            ),
          );
        }
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
