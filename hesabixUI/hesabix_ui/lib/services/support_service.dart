import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:dio/dio.dart';

class SupportService {
  final ApiClient _apiClient;

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
