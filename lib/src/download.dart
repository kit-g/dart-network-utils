import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<http.Response> _get(String url) => http.get(Uri.parse(url));

Future<Uint8List> getRawNetworkFileBytes(String fileUrl) => _get(fileUrl).then((response) => response.bodyBytes);

Future<String> getPage(String url) => _get(url).then((response) => response.body);
