import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../services/announcements_service.dart';

/// Unified navigation + read-state handling for in-app announcements.
class AnnouncementNavigation {
  AnnouncementNavigation._();

  static const _operatorTicketEvents = <String>{
    'support.ticket_created',
    'support.user_reply',
    'support.ticket_assigned',
    'support.tickets_bulk_assigned',
  };

  static const _userTicketEvents = <String>{
    'support.operator_reply',
    'support.ticket_status_changed',
    'support.tickets_bulk_status_changed',
  };

  static Map<String, dynamic> normalizeItem(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'id': raw['id'],
      'title': '${raw['title'] ?? 'اعلان'}',
      'body': '${raw['body'] ?? ''}',
      'level': '${raw['level'] ?? 'info'}',
      'is_read': raw['is_read'] == true,
      if (raw['deep_link'] != null && '${raw['deep_link']}'.isNotEmpty)
        'deep_link': '${raw['deep_link']}',
      if (raw['ticket_id'] != null) 'ticket_id': raw['ticket_id'],
      if (raw['event_key'] != null && '${raw['event_key']}'.isNotEmpty)
        'event_key': '${raw['event_key']}',
    };
  }

  static int? parseAnnouncementId(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  static int? parseTicketId(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    final parsed = int.tryParse('$value');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static bool? _isSupportOperator() {
    return ApiClient.getAuthStore()?.canAccessSupportOperator;
  }

  static bool _isOperatorEvent(String eventKey) {
    if (_operatorTicketEvents.contains(eventKey)) return true;
    return eventKey.contains('operator') ||
        eventKey.endsWith('_assigned') ||
        eventKey.endsWith('_created');
  }

  static bool _isUserEvent(String eventKey) {
    if (_userTicketEvents.contains(eventKey)) return true;
    return eventKey.contains('user_reply') || eventKey.contains('status_changed');
  }

  /// Resolve a navigable route for an announcement item.
  static String? resolveDeepLink(
    Map<String, dynamic> item, {
    bool? isSupportOperator,
  }) {
    final explicit = item['deep_link']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final eventKey = item['event_key']?.toString() ?? '';
    final ticketId = parseTicketId(item['ticket_id']);
    final operator = isSupportOperator ?? _isSupportOperator() ?? false;

    if (ticketId != null) {
      if (_isOperatorEvent(eventKey)) {
        return '/user/profile/operator?ticket=$ticketId';
      }
      if (_isUserEvent(eventKey) || eventKey.startsWith('support.')) {
        return operator && _isOperatorEvent(eventKey)
            ? '/user/profile/operator?ticket=$ticketId'
            : '/user/profile/support/tickets/$ticketId';
      }
      return operator
          ? '/user/profile/operator?ticket=$ticketId'
          : '/user/profile/support/tickets/$ticketId';
    }

    if (eventKey == 'support.tickets_bulk_assigned' || (eventKey.startsWith('support.') && _isOperatorEvent(eventKey))) {
      return operator ? '/user/profile/operator' : null;
    }
    if (eventKey == 'support.tickets_bulk_status_changed' || (eventKey.startsWith('support.') && _isUserEvent(eventKey))) {
      return '/user/profile/support';
    }
    return null;
  }

  static bool hasNavigableTarget(Map<String, dynamic> item, {bool? isSupportOperator}) {
    return resolveDeepLink(item, isSupportOperator: isSupportOperator) != null;
  }

  /// Mark announcement as read (if needed) and navigate to its target route.
  static Future<bool> handleTap(
    BuildContext context,
    Map<String, dynamic> item, {
    bool? isSupportOperator,
    VoidCallback? onBeforeNavigate,
    void Function(int announcementId)? onMarkedRead,
    bool showMarkReadSnackBar = false,
  }) async {
    final normalized = normalizeItem(item);
    final annId = parseAnnouncementId(normalized['id']);
    final route = resolveDeepLink(normalized, isSupportOperator: isSupportOperator);
    final isRead = normalized['is_read'] == true;

    if (annId != null && !isRead) {
      try {
        await AnnouncementsService(ApiClient()).markRead(annId);
        onMarkedRead?.call(annId);
        if (showMarkReadSnackBar && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('به‌عنوان خوانده‌شده علامت خورد')),
          );
        }
      } catch (_) {
        // Navigation should still proceed when possible.
      }
    }

    if (route != null && route.isNotEmpty) {
      onBeforeNavigate?.call();
      if (context.mounted) {
        context.go(route);
      }
      return true;
    }
    return annId != null;
  }
}
