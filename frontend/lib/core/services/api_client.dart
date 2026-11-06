import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'ritech_access_token';
  static const refreshTokenKey = 'ritech_refresh_token';
  static const organizationKey = 'ritech_active_organization';
  static const _requestTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _storage;
  String? exceptionalAccessReason;

  Future<List<dynamic>> getList(String path) async {
    final response = await _send('GET', path);
    final decoded = _decode(response.body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      return decoded['results'] as List<dynamic>;
    }
    return [];
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await _send('GET', path);
    final decoded = _decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _send('POST', path, body: data);
    final decoded = _decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _send('PUT', path, body: data);
    final decoded = _decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _send('PATCH', path, body: data);
    final decoded = _decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<List<Map<String, dynamic>>> getAll(String path) async {
    final records = <Map<String, dynamic>>[];
    String? next = path;
    while (next != null) {
      final response = await _send('GET', next);
      final decoded = _decode(response.body);
      if (decoded is List) {
        records.addAll(decoded.cast<Map<String, dynamic>>());
        break;
      }
      final page = decoded as Map<String, dynamic>;
      records.addAll(
        (page['results'] as List? ?? []).cast<Map<String, dynamic>>(),
      );
      final url = page['next'] as String?;
      if (url == null) {
        next = null;
      } else {
        final uri = Uri.parse(url);
        final base = Uri.parse(ApiConfig.baseUrl);
        if (uri.host != base.host || uri.port != base.port) {
          throw const ApiException('Enlace de paginación inválido.');
        }
        next = '${uri.path.substring(base.path.length)}?${uri.query}';
      }
    }
    return records;
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<String?> get accessToken => _storage.read(key: accessTokenKey);

  Future<String?> get activeOrganizationId =>
      _storage.read(key: organizationKey);

  Future<void> setActiveOrganization(String? organizationId) async {
    if (organizationId == null) {
      await _storage.delete(key: organizationKey);
    } else {
      await _storage.write(key: organizationKey, value: organizationId);
    }
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: accessTokenKey, value: accessToken);
    await _storage.write(key: refreshTokenKey, value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await setActiveOrganization(null);
    exceptionalAccessReason = null;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final token = await accessToken;
    final organizationId = await activeOrganizationId;
    final headers = {
      'Content-Type': 'application/json',
      'X-Access-Reason': ?exceptionalAccessReason,
      if (token != null) 'Authorization': 'Bearer $token',
    };
    if (organizationId != null) {
      headers['X-Organization-ID'] = organizationId;
    }
    final encoded = body == null ? null : jsonEncode(body);
    final request = switch (method) {
      'GET' => http.get(uri, headers: headers),
      'POST' => http.post(uri, headers: headers, body: encoded),
      'PUT' => http.put(uri, headers: headers, body: encoded),
      'PATCH' => http.patch(uri, headers: headers, body: encoded),
      'DELETE' => http.delete(uri, headers: headers),
      _ => throw const ApiException('Metodo HTTP no soportado.'),
    };
    final http.Response response;
    try {
      response = await request.timeout(
        _requestTimeout,
        onTimeout: () {
          throw ApiException(
            'No pudimos conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
          );
        },
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'No pudimos conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    if (response.statusCode == 401) {
      await clearTokens();
    }
    throw ApiException(
      _extractError(response.body),
      statusCode: response.statusCode,
    );
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return {};
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const ApiException(
        'El servidor devolvió una respuesta que no pudimos leer. Inténtalo de nuevo.',
      );
    }
  }

  String _extractError(String body) {
    dynamic decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      return 'El servidor no pudo completar la solicitud. Inténtalo de nuevo en unos momentos.';
    }
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'] ?? decoded['non_field_errors'];
      if (detail is List && detail.isNotEmpty) return detail.first.toString();
      if (detail is String) return detail;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return 'No fue posible completar la solicitud.';
  }
}
