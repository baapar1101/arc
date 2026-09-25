import 'dart:typed_data';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:dio/dio.dart';

class SupportService {
  final ApiClient _apiClient;

  /// حداکثر take مجاز در QueryInfo سمت API
  static const int maxQueryPageSize = 100;

  SupportService(this._apiClient);

  // Categories
  Future<List<SupportCategory>> getCategories() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/metadata/categories');
      return (response.data!['data'] as List).map((json) => SupportCategory.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Priorities
  Future<List<SupportPriority>> getPriorities() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/metadata/priorities');
      return (response.data!['data'] as List).map((json) => SupportPriority.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Statuses
  Future<List<SupportStatus>> getStatuses() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/metadata/statuses');
      return (response.data!['data'] as List).map((json) => SupportStatus.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // User tickets
  Future<PaginatedResponse<SupportTicket>> searchUserTickets(Map<String, dynamic> queryInfo) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/search',
        data: queryInfo,
      );
      return PaginatedResponse.fromJson(
        response.data!['data'],
        (json) => SupportTicket.fromJson(json),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> createTicket(CreateTicketRequest request) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support',
        data: request.toJson(),
      );
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> getTicket(int ticketId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/support/$ticketId');
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> closeTicket(int ticketId) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>('/api/v1/support/$ticketId/close');
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> reopenTicket(int ticketId) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>('/api/v1/support/$ticketId/reopen');
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportMessage> sendMessage(int ticketId, CreateMessageRequest request) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/$ticketId/messages',
        data: request.toJson(),
      );
      return SupportMessage.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<PaginatedResponse<SupportMessage>> searchTicketMessages(
    int ticketId,
    Map<String, dynamic> queryInfo,
  ) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/$ticketId/messages/search',
        data: queryInfo,
      );
      return PaginatedResponse.fromJson(
        response.data!['data'],
        (json) => SupportMessage.fromJson(json),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Operator tickets
  Future<PaginatedResponse<SupportTicket>> searchOperatorTickets(Map<String, dynamic> queryInfo) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/search',
        data: queryInfo,
      );
      return PaginatedResponse.fromJson(
        response.data!['data'],
        (json) => SupportTicket.fromJson(json),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> getOperatorTicket(int ticketId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/support/operator/tickets/$ticketId');
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> updateTicketStatus(int ticketId, UpdateStatusRequest request) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/$ticketId/status',
        data: request.toJson(),
      );
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> assignTicket(int ticketId, AssignTicketRequest request) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/$ticketId/assign',
        data: request.toJson(),
      );
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportTicket> updateTicketPriority(int ticketId, UpdatePriorityRequest request) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/$ticketId/priority',
        data: request.toJson(),
      );
      return SupportTicket.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<SupportOperatorInfo>> getSupportOperators() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/support/operator/operators');
      return (response.data!['data'] as List)
          .map((json) => SupportOperatorInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportMessage> sendOperatorMessage(int ticketId, CreateMessageRequest request) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/$ticketId/messages',
        data: request.toJson(),
      );
      return SupportMessage.fromJson(response.data!['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<PaginatedResponse<SupportMessage>> searchOperatorTicketMessages(
    int ticketId,
    Map<String, dynamic> queryInfo,
  ) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/$ticketId/messages/search',
        data: queryInfo,
      );
      return PaginatedResponse.fromJson(
        response.data!['data'],
        (json) => SupportMessage.fromJson(json),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<SupportMessage>> getAllTicketMessages(
    int ticketId, {
    required bool isOperator,
  }) async {
    final all = <SupportMessage>[];
    var skip = 0;

    while (true) {
      final response = isOperator
          ? await searchOperatorTicketMessages(ticketId, {
              'take': maxQueryPageSize,
              'skip': skip,
              'sort_by': 'created_at',
              'sort_desc': false,
            })
          : await searchTicketMessages(ticketId, {
              'take': maxQueryPageSize,
              'skip': skip,
              'sort_by': 'created_at',
              'sort_desc': false,
            });

      all.addAll(response.items);
      if (all.length >= response.total || response.items.length < maxQueryPageSize) {
        break;
      }
      skip += response.items.length;
    }

    return all;
  }

  // حذف تیکت (فقط برای مدیر سیستم)
  Future<void> deleteTicket(int ticketId) async {
    try {
      await _apiClient.delete(
        '/api/v1/support/operator/tickets/$ticketId',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // حذف چندین تیکت به صورت گروهی (فقط برای مدیر سیستم)
  Future<Map<String, dynamic>> deleteTickets(List<int> ticketIds) async {
    try {
      final results = <int, dynamic>{};
      
      for (final ticketId in ticketIds) {
        try {
          await deleteTicket(ticketId);
          results[ticketId] = {'success': true};
        } catch (e) {
          results[ticketId] = {
            'success': false,
            'error': ErrorExtractor.userMessage(e),
          };
        }
      }
      
      final successCount = results.values.where((r) => r['success'] == true).length;
      final failCount = results.values.where((r) => r['success'] == false).length;
      
      return {
        'total': ticketIds.length,
        'success': successCount,
        'failed': failCount,
        'results': results,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Bulk operations
  Future<Map<String, dynamic>> bulkAssignTickets(List<int> ticketIds, int operatorId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/bulk-assign',
        data: {
          'ticket_ids': ticketIds,
          'operator_id': operatorId,
        },
      );
      return response.data!['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> bulkUpdateStatus(
    List<int> ticketIds,
    int statusId, {
    int? assignedOperatorId,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/support/operator/tickets/bulk-update-status',
        data: {
          'ticket_ids': ticketIds,
          'status_id': statusId,
          if (assignedOperatorId != null) 'assigned_operator_id': assignedOperatorId,
        },
      );
      return response.data!['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<SupportTicketEvent>> getTicketEvents(int ticketId, {required bool isOperator}) async {
    try {
      final path = isOperator
          ? '/api/v1/support/operator/tickets/$ticketId/events'
          : '/api/v1/support/$ticketId/events';
      final response = await _apiClient.get<Map<String, dynamic>>(path);
      return (response.data!['data'] as List)
          .map((json) => SupportTicketEvent.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SupportAttachment> uploadAttachment(
    int ticketId,
    Uint8List bytes,
    String filename, {
    required bool isOperator,
  }) async {
    try {
      final path = isOperator
          ? '/api/v1/support/operator/tickets/$ticketId/attachments'
          : '/api/v1/support/$ticketId/attachments';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _apiClient.post<Map<String, dynamic>>(path, data: formData);
      return SupportAttachment.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<int>> downloadAttachment(int attachmentId, {required bool isOperator}) async {
    try {
      final path = attachmentDownloadPath(attachmentId, isOperator: isOperator);
      final response = await _apiClient.get<List<int>>(
        path,
        responseType: ResponseType.bytes,
      );
      return response.data ?? [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String attachmentDownloadPath(int attachmentId, {required bool isOperator}) {
    return isOperator
        ? '/api/v1/support/operator/attachments/$attachmentId/download'
        : '/api/v1/support/attachments/$attachmentId/download';
  }

  Future<List<ServerResponseTemplate>> getResponseTemplates() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/support/operator/templates');
      return (response.data!['data'] as List)
          .map((json) => ServerResponseTemplate.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getOperatorDashboardStats() async {
    final response = await _apiClient.get<Map<String, dynamic>>('/api/v1/support/operator/dashboard/stats');
    return Map<String, dynamic>.from(response.data!['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> getOperatorDashboardOverdue({int limit = 20}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/support/operator/dashboard/overdue',
      query: {'limit': limit},
    );
    return (response.data!['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getOperatorDashboardActivity({int days = 7}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/support/operator/dashboard/activity',
      query: {'days': days},
    );
    return (response.data!['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getOperatorUserTicketHistory(int userId, {int take = 5}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/support/operator/users/$userId/tickets',
      query: {'take': take},
    );
    return (response.data!['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> markUserTicketRead(int ticketId) async {
    await _apiClient.post<Map<String, dynamic>>('/api/v1/support/$ticketId/read');
  }

  Future<void> markOperatorTicketRead(int ticketId) async {
    await _apiClient.post<Map<String, dynamic>>('/api/v1/support/operator/tickets/$ticketId/read');
  }

  Future<SupportTicket> submitTicketCsat(int ticketId, {required int rating, String? comment}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/support/$ticketId/csat',
      data: {'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment},
    );
    return SupportTicket.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  // Error handling
  Exception _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic> && data.containsKey('detail')) {
        return Exception(data['detail']);
      }
    }
    return Exception(e.message ?? 'خطای نامشخص');
  }
}
