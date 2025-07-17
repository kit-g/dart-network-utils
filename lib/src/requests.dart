import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

typedef Json = Map<String, dynamic>;
typedef Response = (Json, int);

/// Mixin providing HTTP request methods (GET, POST, PUT, DELETE) and utilities
/// for sending and handling API requests.
///
/// This mixin is meant to be used with classes that define an `API gateway`
/// and set `default headers`. It uses the `http` package for performing HTTP
/// requests and provides a response processing mechanism.
///
/// Classes mixing in `Requests` must implement:
/// - [gateway]: The API base URL.
/// - [defaultHeaders]: Optional headers to include in each request.
///
/// Features:
/// - Automatic processing of HTTP responses.
/// - Logging of successful and failed requests.
/// - Support for JSON payloads and query parameters for GET, POST, PUT, and DELETE.
///
/// Typical usage involves overriding the [gateway] and [defaultHeaders] properties.
///
/// ```dart
/// class MyApiClient with Requests {
///   @override
///   String get gateway => 'api.example.com';
///
///   @override
///   Map<String, String>? get defaultHeaders => {
///     'Authorization': 'Bearer <your_token_here>',
///     'Content-Type': 'application/json',
///   };
/// }
///
/// void main() async {
///   final client = MyApiClient();
///
///   try {
///     // Sending a GET request
///     final response = await client.get('/endpoint');
///     print('Response Data: ${response.$1}, Status Code: ${response.$2}');
///   } catch (e) {
///     print('Error: $e');
///   }
/// }
/// ```
abstract mixin class Requests {
  /// HTTP client to use for making requests.
  http.Client? get client;

  /// API domain with no prefix, e.g.: api.example.com
  String get gateway;

  /// headers to be included in every request
  Map<String, String>? get defaultHeaders;

  bool get allowInsecure => false;

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
    var url = (allowInsecure ? Uri.http : Uri.https)(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return (client?.get ?? http.get)(url, headers: merged).then<Response>(_process);
  }

  Future<Response> post(String endpoint, {Map<String, String>? headers, Json? body, Map<String, dynamic>? query}) {
    var url = (allowInsecure ? Uri.http : Uri.https)(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return (client?.post ?? http.post)(url, headers: merged, body: jsonEncode(body)).then<Response>(_process);
  }

  Future<Response> put(String endpoint, {Map<String, String>? headers, Json? body}) {
    var url = (allowInsecure ? Uri.http : Uri.https)(gateway, endpoint);
    var merged = {...?headers, ...?defaultHeaders};
    return (client?.put ?? http.put)(url, headers: merged, body: jsonEncode(body)).then<Response>(_process);
  }

  Future<Response> delete(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = (allowInsecure ? Uri.http : Uri.https)(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return (client?.delete ?? http.delete)(url, headers: merged).then<Response>(_process);
  }

  Future<Response> head(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = (allowInsecure ? Uri.http : Uri.https)(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    return (client?.head ?? http.head)(url, headers: merged).then<Response>(_process);
  }
}

MapEntry<String, String> _cast(String k, dynamic v) => MapEntry(k, v.toString());

class NetworkException implements Exception {
  final int statusCode;
  final Map? body;

  const NetworkException({
    required this.statusCode,
    this.body,
  });
}
