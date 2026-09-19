import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

const _sectionSeparator = '────────────────────────────────';

/// Copies [text] to the clipboard and shows a snackbar when [context] is still mounted.
Future<void> copySupportTextToClipboard(
  BuildContext context,
  String text, {
  String? emptyMessage,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    if (emptyMessage != null && context.mounted) {
      SnackBarHelper.show(context, message: emptyMessage);
    }
    return;
  }

  await Clipboard.setData(ClipboardData(text: trimmed));
  if (!context.mounted) return;
  SnackBarHelper.show(context, message: AppLocalizations.of(context).copied);
}

String supportMessageSenderLabel(SupportMessage message) {
  if (message.isInternal) {
    final name = message.sender?.displayName.trim();
    if (name != null && name.isNotEmpty) {
      return '$name (یادداشت داخلی)';
    }
    return 'اپراتور (یادداشت داخلی)';
  }
  if (message.isFromSystem) return 'سیستم';
  if (message.isFromOperator) {
    return message.sender?.displayName.trim().isNotEmpty == true
        ? message.sender!.displayName
        : 'اپراتور';
  }
  return message.sender?.displayName.trim().isNotEmpty == true
      ? message.sender!.displayName
      : 'کاربر';
}

String formatSupportMessageForClipboard({
  required SupportMessage message,
  required String Function(DateTime) formatDateTime,
}) {
  final localCreatedAt = message.createdAt.isUtc ? message.createdAt.toLocal() : message.createdAt;
  final buf = StringBuffer()
    ..writeln('[${formatDateTime(localCreatedAt)}] ${supportMessageSenderLabel(message)}');

  final content = message.content.trim();
  if (content.isNotEmpty) {
    buf.writeln(content);
  }

  final attachments = message.attachments;
  if (attachments != null && attachments.isNotEmpty) {
    final names = attachments.map((a) => a.originalName.trim()).where((name) => name.isNotEmpty);
    if (names.isNotEmpty) {
      buf.writeln('[پیوست: ${names.join('، ')}]');
    }
  }

  return buf.toString().trimRight();
}

String formatSupportTicketForClipboard({
  required SupportTicket ticket,
  required List<SupportMessage> messages,
  required bool includeInternalNotes,
  required String Function(DateTime) formatDateTime,
}) {
  final buf = StringBuffer();

  buf.writeln('تیکت #${ticket.id} — ${ticket.title.trim()}');

  final meta = <String>[];
  final userName = ticket.user?.displayName.trim();
  if (userName != null && userName.isNotEmpty) meta.add('کاربر: $userName');
  final statusName = ticket.status?.name.trim();
  if (statusName != null && statusName.isNotEmpty) meta.add('وضعیت: $statusName');
  final priorityName = ticket.priority?.name.trim();
  if (priorityName != null && priorityName.isNotEmpty) meta.add('اولویت: $priorityName');
  final categoryName = ticket.category?.name.trim();
  if (categoryName != null && categoryName.isNotEmpty) meta.add('دسته‌بندی: $categoryName');
  final operatorName = ticket.assignedOperator?.displayName.trim();
  if (operatorName != null && operatorName.isNotEmpty) meta.add('اپراتور: $operatorName');
  meta.add(
    'ایجاد: ${formatDateTime(ticket.createdAt.isUtc ? ticket.createdAt.toLocal() : ticket.createdAt)}',
  );
  if (meta.isNotEmpty) {
    buf.writeln(meta.join(' | '));
  }

  final description = ticket.description.trim();
  final visibleMessages = includeInternalNotes
      ? List<SupportMessage>.from(messages)
      : messages.where((message) => !message.isInternal).toList(growable: false);

  if (description.isNotEmpty) {
    buf
      ..writeln(_sectionSeparator)
      ..writeln('[درخواست اولیه]')
      ..writeln(description);
  }

  if (visibleMessages.isNotEmpty) {
    if (description.isNotEmpty || buf.isNotEmpty) {
      buf.writeln(_sectionSeparator);
    }
    buf.writeln('[مکالمه]');
    for (var i = 0; i < visibleMessages.length; i++) {
      if (i > 0) buf.writeln();
      buf.write(
        formatSupportMessageForClipboard(
          message: visibleMessages[i],
          formatDateTime: formatDateTime,
        ),
      );
    }
  }

  return buf.toString().trim();
}
