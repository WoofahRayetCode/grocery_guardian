import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Optimized HTTP client singleton with connection pooling and HTTPS enforcement.
/// Uses a persistent client instance for connection reuse across requests.
class SecureHttp {
  SecureHttp._internal();
  static final SecureHttp instance = SecureHttp._internal();

  // Persistent client for connection reuse - improves performance
  http.Client? _client;
  
  http.Client get _httpClient => _client ??= http.Client();

  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const String _userAgent = 'GroceryGuardian/1.0 (+https://github.com/WoofahRayetCode/grocery_guardian)';

  Map<String, String> _baseHeaders() => const {
        'User-Agent': _userAgent,
      };

  /// GET request with HTTPS enforcement and timeout
  Future<http.Response> get(Uri uri, {Map<String, String>? headers, Duration? timeout}) {
    if (uri.scheme != 'https') {
      throw const HttpException('Insecure URL blocked (HTTPS required)');
    }
    final merged = {..._baseHeaders(), if (headers != null) ...headers};
    return _httpClient.get(uri, headers: merged).timeout(timeout ?? _defaultTimeout);
  }

  /// POST request with HTTPS enforcement and timeout
  Future<http.Response> post(Uri uri, {Map<String, String>? headers, Object? body, Encoding? encoding, Duration? timeout}) {
    if (uri.scheme != 'https') {
      throw const HttpException('Insecure URL blocked (HTTPS required)');
    }
    final merged = {..._baseHeaders(), if (headers != null) ...headers};
    return _httpClient.post(uri, headers: merged, body: body, encoding: encoding).timeout(timeout ?? _defaultTimeout);
  }

  /// Close the HTTP client to free resources. Call when app is terminating.
  void dispose() {
    _client?.close();
    _client = null;
  }
}
