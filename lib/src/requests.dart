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

  /// a callback to be invoked on Upgrade Required rejection, usually HTTP code 426
  Response Function(Json)? onUpgradeRequired;

  /// a callback to be invoked on Unauthorized rejection, usually HTTP code 401
  Response Function(Json)? onUnauthorized;

  /// Async callback to attempt reauthentication on 401.
  /// Return `true` if reauthentication succeeded and the request should be retried.
  Future<bool> Function()? onReauthenticate;

  final _logger = Logger('Requests');

  void _success(String? endpoint, int statusCode, String verb) {
    _logger.info('$verb on ${endpoint ?? "unknown endpoint"}: $statusCode');
  }

  void _failure(String? endpoint, int statusCode, String verb, {Json? body}) {
    var payload = switch (body) { Json j => 'with payload: $j', null => 'with no payload' };
    _logger.shout('$verb on ${endpoint ?? "unknown endpoint"}: $statusCode $payload');
  }

  static bool _isPositive(int statusCode) => 300 > statusCode && statusCode >= 200;

  Response _process(http.Response response, {bool allowRetry = true}) {
    final http.Response(:statusCode, body: r, :request) = response;
    final http.BaseRequest(:Uri url, :method) = request!;
    try {
      if (jsonDecode(r) case Json json) {
        switch (statusCode) {
          case 401:
            _failure(url.path, statusCode, method, body: json);
            return onUnauthorized?.call(json) ?? (json, 401);
          case 426:
            _failure(url.path, statusCode, method, body: json);
            return onUpgradeRequired?.call(json) ?? (json, 426);
          case >= 200 && < 300:
            _success(url.path, statusCode, method);
            return (json, statusCode);
          default:
            _failure(url.path, statusCode, method, body: json);
            return (json, statusCode);
        }
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

  Future<Response> _processWithRetry(
    http.Response response,
    Future<http.Response> Function() retry,
  ) async {
    final statusCode = response.statusCode;

    // On 401, try reauthentication and retry once
    if (statusCode == 401 && onReauthenticate != null) {
      _logger.info('Reauthenticating');
      final success = await onReauthenticate!();
      if (success) {
        _logger.info('Success reauthenticating');
        final retryResponse = await retry();
        _logger.info('Retrying the original call');
        return _process(retryResponse, allowRetry: false);
      }
    }

    return _process(response, allowRetry: false);
  }

  Future<Response> get(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    Future<http.Response> doRequest() => (client?.get ?? http.get)(url, headers: merged);
    return doRequest().then((r) => _processWithRetry(r, doRequest));
  }

  Future<Response> post(String endpoint, {Map<String, String>? headers, Json? body, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    Future<http.Response> doRequest() => (client?.post ?? http.post)(url, headers: merged, body: jsonEncode(body));
    return doRequest().then((r) => _processWithRetry(r, doRequest));
  }

  Future<Response> put(String endpoint, {Map<String, String>? headers, Json? body}) {
    var url = Uri.https(gateway, endpoint);
    var merged = {...?headers, ...?defaultHeaders};
    Future<http.Response> doRequest() => (client?.put ?? http.put)(url, headers: merged, body: jsonEncode(body));
    return doRequest().then((r) => _processWithRetry(r, doRequest));
  }

  Future<Response> delete(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    var merged = {...?headers, ...?defaultHeaders};
    Future<http.Response> doRequest() => (client?.delete ?? http.delete)(url, headers: merged);
    return doRequest().then((r) => _processWithRetry(r, doRequest));
  }

  Future<Response> head(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? query}) {
    var url = Uri.https(gateway, endpoint, query?.map(_cast));
    Future<http.Response> doRequest() => (client?.head ?? http.head)(url, headers: {...?headers, ...?defaultHeaders});
    return doRequest().then((r) => _processWithRetry(r, doRequest));
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
