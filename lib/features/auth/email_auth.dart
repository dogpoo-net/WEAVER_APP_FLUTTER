import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailAuthFailure implements Exception {
  const EmailAuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server-issued credentials are held in memory, never in the test Google marker.
class EmailAuthApi {
  EmailAuthApi({http.Client? client, Uri? base})
      : _client = client ?? http.Client(),
        _base = base ?? Uri.parse(const String.fromEnvironment('WEAVER_AUTH_URL',
            defaultValue: 'https://api.dogpoo.net/dogpoo/weaver/api/auth/'));
  final http.Client _client;
  final Uri _base;
  Future<Map<String, dynamic>> post(String action, Map<String, String> body,
      {String? sessionToken}) async {
    try {
      final response = await _client.post(_base.resolve(action), headers: {
        'Content-Type': 'application/json',
        if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
      }, body: jsonEncode(body)).timeout(const Duration(seconds: 35));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw EmailAuthFailure(data is Map && data['message'] is String
            ? data['message'] as String : '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.');
      }
      return Map<String, dynamic>.from(data as Map);
    } on EmailAuthFailure { rethrow; }
    catch (_) { throw const EmailAuthFailure('서버에 연결하지 못했습니다. 연결을 확인하고 다시 시도해주세요.'); }
  }
  void dispose() => _client.close();
}
