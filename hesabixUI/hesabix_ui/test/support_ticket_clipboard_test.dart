import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/support_ticket_clipboard.dart';

SupportMessage _message({
  required int id,
  required String senderType,
  required String content,
  bool isInternal = false,
  String? firstName,
  String? lastName,
  List<SupportAttachment>? attachments,
}) {
  return SupportMessage(
    id: id,
    ticketId: 42,
    senderId: id,
    senderType: senderType,
    content: content,
    isInternal: isInternal,
    createdAt: DateTime(2026, 3, 15, 14, 30),
    sender: firstName == null && lastName == null
        ? null
        : SupportUser(
            id: id,
            email: '$id@example.com',
            firstName: firstName,
            lastName: lastName,
          ),
    attachments: attachments,
  );
}

SupportTicket _ticket({String description = 'مشکل در ورود به سیستم'}) {
  final now = DateTime(2026, 3, 15, 10, 0);
  return SupportTicket(
    id: 42,
    title: 'خطای ورود',
    description: description,
    userId: 7,
    categoryId: 1,
    priorityId: 2,
    statusId: 3,
    isInternal: false,
    createdAt: now,
    updatedAt: now.add(const Duration(hours: 4, minutes: 45)),
    user: SupportUser(id: 7, email: 'user@example.com', firstName: 'علی', lastName: 'رضایی'),
    assignedOperator: SupportUser(id: 9, email: 'op@example.com', firstName: 'سارا'),
    category: SupportCategory(
      id: 1,
      name: 'فنی',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
    priority: SupportPriority(
      id: 2,
      name: 'بالا',
      color: '#ff0000',
      order: 3,
      createdAt: now,
      updatedAt: now,
    ),
    status: SupportStatus(
      id: 3,
      name: 'باز',
      color: '#00ff00',
      isFinal: false,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

String _formatDate(DateTime date) => '2026/03/15 14:30';

void main() {
  group('formatSupportMessageForClipboard', () {
    test('includes sender, timestamp, and content', () {
      final text = formatSupportMessageForClipboard(
        message: _message(id: 1, senderType: 'user', content: 'سلام', firstName: 'علی'),
        formatDateTime: _formatDate,
      );

      expect(text, contains('[2026/03/15 14:30]'));
      expect(text, contains('علی'));
      expect(text, contains('سلام'));
    });

    test('labels internal notes', () {
      final text = formatSupportMessageForClipboard(
        message: _message(
          id: 2,
          senderType: 'operator',
          content: 'بررسی شد',
          isInternal: true,
          firstName: 'سارا',
        ),
        formatDateTime: _formatDate,
      );

      expect(text, contains('سارا (یادداشت داخلی)'));
      expect(text, contains('بررسی شد'));
    });

    test('includes attachment names', () {
      final text = formatSupportMessageForClipboard(
        message: _message(
          id: 3,
          senderType: 'user',
          content: 'فایل پیوست شد',
          attachments: [
            SupportAttachment(
              id: 10,
              ticketId: 42,
              fileStorageId: 'abc',
              originalName: 'screenshot.png',
              sizeBytes: 100,
              uploadedBy: 7,
              createdAt: DateTime(2026, 3, 15, 14, 30),
            ),
          ],
        ),
        formatDateTime: _formatDate,
      );

      expect(text, contains('[پیوست: screenshot.png]'));
    });
  });

  group('formatSupportTicketForClipboard', () {
    test('formats ticket metadata, initial request, and conversation', () {
      final text = formatSupportTicketForClipboard(
        ticket: _ticket(),
        messages: [
          _message(id: 1, senderType: 'user', content: 'هنوز حل نشده', firstName: 'علی', lastName: 'رضایی'),
          _message(
            id: 2,
            senderType: 'operator',
            content: 'در حال بررسی',
            firstName: 'سارا',
          ),
        ],
        includeInternalNotes: true,
        formatDateTime: _formatDate,
      );

      expect(text, contains('تیکت #42 — خطای ورود'));
      expect(text, contains('کاربر: علی رضایی'));
      expect(text, contains('وضعیت: باز'));
      expect(text, contains('[درخواست اولیه]'));
      expect(text, contains('مشکل در ورود به سیستم'));
      expect(text, contains('[مکالمه]'));
      expect(text, contains('هنوز حل نشده'));
      expect(text, contains('در حال بررسی'));
    });

    test('excludes internal notes when includeInternalNotes is false', () {
      final text = formatSupportTicketForClipboard(
        ticket: _ticket(description: ''),
        messages: [
          _message(id: 1, senderType: 'user', content: 'پیام عمومی'),
          _message(
            id: 2,
            senderType: 'operator',
            content: 'یادداشت مخفی',
            isInternal: true,
          ),
        ],
        includeInternalNotes: false,
        formatDateTime: _formatDate,
      );

      expect(text, contains('پیام عمومی'));
      expect(text, isNot(contains('یادداشت مخفی')));
    });
  });
}
