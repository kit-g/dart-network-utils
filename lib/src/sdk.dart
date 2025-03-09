import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

typedef Json = Map<String, dynamic>;
typedef Response = (Json, int);

class NetworkException implements Exception {
  final int statusCode;
  final Map? body;

  const NetworkException({
    required this.statusCode,
    this.body,
  });
}

abstract mixin class Requests {
  /// API domain with no prefix, e.g.: api.example.com
  String get gateway;

  /// headers to be included in every request
  Map<String, String>? get defaultHeaders;

  final _logger = Logger('SDK');

  void _success(String? endpoint, int statusCode, String verb) {
    _logger.info('$verb on ${endpoint ?? "unknown endpoint"}: $statusCode');
  }

  void _failure(String? endpoint, int statusCode, String verb, {Json? body}) {
    var payload = switch (body) { Json j => 'with payload: $j', null => 'with no payload' };
    _logger.shout('$verb on ${endpoint ?? "unknown endpoint"}: $statusCode $payload');
  }

  static bool _isPositive(int statusCode) => 300 > statusCode && statusCode >= 200;

  Response _process(http.Response response) {
    final http.Response(:statusCode, body: r, :request) = response;
    final http.BaseRequest(:Uri url, :method) = request!;
    try {
      if (jsonDecode(r) case Json json) {
        if (_isPositive(statusCode)) {
          _success(url.path, statusCode, method);
        } else {
          _failure(url.path, statusCode, method, body: json);
        }
        return (json, statusCode);
      }
      _failure(url.path, statusCode, method);
      throw NetworkException(statusCode: statusCode);
    } on FormatException catch (e) {
      // empty positive response, e.g. 204
      if (_isPositive(statusCode) && ((e.offset ?? 0) == 0)) {
        _success(url.path, statusCode, method);
        return ({}, statusCode);
      }
      rethrow;
    }
  }

  Future<Response> get(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return http.get(url, headers: merged).then<Response>(_process);
  }

  Future<Response> post(String endpoint, {Map<String, String>? headers, Json? body, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return http.post(url, headers: merged, body: jsonEncode(body)).then<Response>(_process);
  }

  Future<Response> put(String endpoint, {Map<String, String>? headers, Json? body}) {
    var url = Uri.https(gateway, endpoint);
    var merged = {...?headers, ...?defaultHeaders};
    return http.put(url, headers: merged, body: jsonEncode(body)).then<Response>(_process);
  }

  Future<Response> delete(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return http.delete(url, headers: merged).then<Response>(_process);
  }
}

MapEntry<String, String> _cast(String k, dynamic v) => MapEntry(k, v.toString());
