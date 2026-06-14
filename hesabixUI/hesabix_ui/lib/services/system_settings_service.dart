import '../core/api_client.dart';

class SystemSettingsService {
  final ApiClient _api;
  SystemSettingsService(this._api);

  Future<Map<String, dynamic>> getWalletSettings() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/system-settings/wallet');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
    }

  Future<Map<String, dynamic>> setWalletBaseCurrencyCode(String code) async {
    final res = await _api.put<Map<String, dynamic>>('/admin/system-settings/wallet', data: {
      'wallet_base_currency_code': code,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> getShareLinkSettings() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/system-settings/share-links');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updateShareLinkSettings(
    String publicAppUrl, {
    double? invoiceGatewayFeePercent,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/admin/system-settings/share-links',
      data: {
        'public_app_url': publicAppUrl,
        if (invoiceGatewayFeePercent != null) 'invoice_gateway_fee_percent': invoiceGatewayFeePercent,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> getMarketplaceSettings() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/system-settings/marketplace');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updateMarketplaceSettings({
    required double publisherSharePercent,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/admin/system-settings/marketplace',
      data: {'publisher_share_percent': publisherSharePercent},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}


