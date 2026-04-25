import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/warranty_service.dart';
import '../../models/warranty_models.dart';
import '../../core/api_client.dart';
import '../../utils/error_extractor.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';

class PublicWarrantyTrackingPage extends StatefulWidget {
  final String? codeOrSerial;
  final String? linkCode;

  const PublicWarrantyTrackingPage({
    super.key,
    this.codeOrSerial,
    this.linkCode,
  });

  @override
  State<PublicWarrantyTrackingPage> createState() => _PublicWarrantyTrackingPageState();
}

class _PublicWarrantyTrackingPageState extends State<PublicWarrantyTrackingPage> {
  final WarrantyService _warrantyService = WarrantyService();
  final _searchController = TextEditingController();
  bool _loading = false;
  WarrantyTrackingInfo? _trackingInfo;
  String? _error;
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _calendarController = ApiClient.getCalendarController();
    if (_calendarController == null) {
      CalendarController.load().then((c) {
        if (mounted) {
          setState(() => _calendarController = c);
        }
      });
    }
    if (widget.linkCode != null) {
      _trackByLink(widget.linkCode!);
    } else if (widget.codeOrSerial != null) {
      _searchController.text = widget.codeOrSerial!;
      _trackWarranty(widget.codeOrSerial!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _trackWarranty(String codeOrSerial) async {
    setState(() {
      _loading = true;
      _error = null;
      _trackingInfo = null;
    });

    try {
      final info = await _warrantyService.trackWarranty(codeOrSerial);
      if (mounted) {
        setState(() {
          _trackingInfo = info;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      if (mounted) {
        setState(() {
          _error = message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'خطا در رهگیری گارانتی: ${ErrorExtractor.forContext(e, context)}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _trackByLink(String linkCode) async {
    setState(() {
      _loading = true;
      _error = null;
      _trackingInfo = null;
    });

    try {
      final info = await _warrantyService.trackWarrantyByLink(linkCode);
      if (mounted) {
        setState(() {
          _trackingInfo = info;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      if (mounted) {
        setState(() {
          _error = message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'خطا در رهگیری گارانتی: ${ErrorExtractor.forContext(e, context)}';
          _loading = false;
        });
      }
    }
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      if (data.containsKey('message')) {
        return data['message'].toString();
      }
      if (data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    return e.message ?? 'خطای نامشخص';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final calendarController = _calendarController;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(t.warrantyTracking),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.linkCode == null) _buildSearchSection(context, theme, colorScheme, t),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _buildErrorView(context, theme, colorScheme, _error!)
                  else if (_trackingInfo != null)
                    calendarController != null
                        ? _buildTrackingInfo(context, theme, colorScheme, t, _trackingInfo!, calendarController)
                        : const Center(child: CircularProgressIndicator())
                  else
                    _buildEmptyState(context, theme, colorScheme, t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  t.trackWarranty,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'کد گارانتی یا سریال را وارد کنید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'کد گارانتی یا سریال',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.qr_code),
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        _trackWarranty(value.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          if (_searchController.text.trim().isNotEmpty) {
                            _trackWarranty(_searchController.text.trim());
                          }
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('جستجو'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    String error,
  ) {
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              error,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(Icons.search, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'برای رهگیری گارانتی، کد یا سریال را وارد کنید',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingInfo(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
    WarrantyTrackingInfo info,
    CalendarController calendarController,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'اطلاعات گارانتی',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInfoRow(context, theme, 'کد گارانتی', info.code),
            _buildInfoRow(context, theme, t.warrantySerial, info.warrantySerial),
            _buildInfoRow(
              context,
              theme,
              t.warrantyStatus,
              _getStatusLabel(info.status, t),
            ),
            if (info.business != null)
              _buildInfoRow(context, theme, 'کسب و کار', info.business!.name ?? '-'),
            if (info.product != null)
              _buildInfoRow(context, theme, t.warrantyProduct, info.product!.name ?? '-'),
            _buildInfoRow(
              context,
              theme,
              t.warrantyGeneratedAt,
              HesabixDateUtils.formatDateTime(info.generatedAt, calendarController?.isJalali ?? true),
            ),
            if (info.activatedAt != null)
              _buildInfoRow(
                context,
                theme,
                t.warrantyActivatedAt,
                HesabixDateUtils.formatDateTime(info.activatedAt!, calendarController?.isJalali ?? true),
              ),
            if (info.expiresAt != null)
              _buildInfoRow(
                context,
                theme,
                t.warrantyExpiresAt,
                HesabixDateUtils.formatDateTime(info.expiresAt!, calendarController?.isJalali ?? true),
              ),
            if (info.trackingEvents.isNotEmpty) ...[
              const SizedBox(height: 24),
              Divider(),
              const SizedBox(height: 16),
              Text(
                t.warrantyEvents,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...info.trackingEvents.map((event) => _buildEventCard(context, theme, event, calendarController)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(
    BuildContext context,
    ThemeData theme,
    WarrantyTracking event,
    CalendarController calendarController,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_getEventIcon(event.eventType)),
        title: Text(_getEventTypeLabel(event.eventType)),
        subtitle: event.description != null ? Text(event.description!) : null,
        trailing: Text(
          HesabixDateUtils.formatDateTime(event.createdAt, calendarController?.isJalali ?? true),
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  IconData _getEventIcon(WarrantyEventType type) {
    switch (type) {
      case WarrantyEventType.activation:
        return Icons.check_circle;
      case WarrantyEventType.repairRequest:
        return Icons.build;
      case WarrantyEventType.repairCompleted:
        return Icons.check;
      case WarrantyEventType.replacement:
        return Icons.swap_horiz;
      case WarrantyEventType.expired:
        return Icons.event_busy;
      case WarrantyEventType.revoked:
        return Icons.cancel;
    }
  }

  String _getEventTypeLabel(WarrantyEventType type) {
    final t = AppLocalizations.of(context);
    switch (type) {
      case WarrantyEventType.activation:
        return t.warrantyEventActivation;
      case WarrantyEventType.repairRequest:
        return t.warrantyEventRepairRequest;
      case WarrantyEventType.repairCompleted:
        return t.warrantyEventRepairCompleted;
      case WarrantyEventType.replacement:
        return t.warrantyEventReplacement;
      case WarrantyEventType.expired:
        return t.warrantyEventExpired;
      case WarrantyEventType.revoked:
        return t.warrantyEventRevoked;
    }
  }

  String _getStatusLabel(WarrantyStatus status, AppLocalizations t) {
    switch (status) {
      case WarrantyStatus.generated:
        return t.warrantyGenerated;
      case WarrantyStatus.activated:
        return t.warrantyActivated;
      case WarrantyStatus.expired:
        return t.warrantyExpired;
      case WarrantyStatus.used:
        return t.warrantyUsed;
      case WarrantyStatus.revoked:
        return t.warrantyRevoked;
    }
  }
}

