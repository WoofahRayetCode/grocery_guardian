import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SecureHttp {
  SecureHttp._internal();
  static final SecureHttp instance = SecureHttp._internal();

  final http.Client _client = http.Client();

  Map<String, String> _baseHeaders() => {
        'User-Agent': 'GroceryGuardian/1.0 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      };

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    if (uri.scheme != 'https') {
      throw const HttpException('Insecure URL blocked (HTTPS required)');
    }
    final merged = {..._baseHeaders(), if (headers != null) ...headers};
    return _client.get(uri, headers: merged).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> post(Uri uri, {Map<String, String>? headers, Object? body, Encoding? encoding}) {
    if (uri.scheme != 'https') {
      throw const HttpException('Insecure URL blocked (HTTPS required)');
    }
    final merged = {..._baseHeaders(), if (headers != null) ...headers};
    return _client.post(uri, headers: merged, body: body, encoding: encoding).timeout(const Duration(seconds: 15));
  }
}
