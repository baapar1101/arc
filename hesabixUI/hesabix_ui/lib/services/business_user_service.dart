import '../core/api_client.dart';
import '../models/business_user_model.dart';

class BusinessUserService {
  final ApiClient _apiClient;

  BusinessUserService(this._apiClient);

  /// Get all users for a business
  Future<BusinessUsersResponse> getBusinessUsers(int businessId) async {
    try {
      final response = await _apiClient.get('/api/v1/business/$businessId/users');
      return BusinessUsersResponse.fromJson(response.data['data']);
    } catch (e) {
      throw Exception('Failed to fetch business users: $e');
    }
  }

  /// Add a new user to business
  Future<AddUserResponse> addUser(AddUserRequest request) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/business/${request.businessId}/users',
        data: request.toJson(),
      );
      return AddUserResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to add user: $e');
    }
  }

  /// Update user permissions
  Future<UpdatePermissionsResponse> updatePermissions(UpdatePermissionsRequest request) async {
    try {
      final response = await _apiClient.put(
        '/api/v1/business/${request.businessId}/users/${request.userId}/permissions',
        data: request.toJson(),
      );
      // API returns {success, message} directly, not wrapped in 'data'
      return UpdatePermissionsResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to update permissions: $e');
    }
  }

  /// Remove user from business
  Future<RemoveUserResponse> removeUser(RemoveUserRequest request) async {
    try {
      final response = await _apiClient.delete(
        '/api/v1/business/${request.businessId}/users/${request.userId}',
      );
      return RemoveUserResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to remove user: $e');
    }
  }

  /// Get user details
  Future<BusinessUser> getUserDetails(int businessId, int userId) async {
    try {
      final response = await _apiClient.get('/api/v1/business/$businessId/users/$userId');
      return BusinessUser.fromJson(response.data['data']['user']);
    } catch (e) {
      throw Exception('Failed to fetch user details: $e');
    }
  }
}