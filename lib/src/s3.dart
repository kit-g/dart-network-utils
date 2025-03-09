import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:logging/logging.dart';

final _logger = Logger('S3');

typedef MultipartFile = (String field, List<int> value, {String? filename, String? contentType});
typedef PreSignedUrl = ({String url, Map<String, String> fields});

/// Parses upload links from a given JSON object and returns a map of keys to PreSignedUrl objects.
///
/// The input JSON must contain a key called `mediaUploadLinks` that maps to
/// another map containing S3 credential data (e.g., URLs and form fields).
///
/// Throws an [ArgumentError] if the JSON data format is incorrect.
///
/// Example:
/// ```dart
/// final uploadLinks = parseUploadLinks({
///   'mediaUploadLinks': {
///     'file1': {
///       'url': 'https://s3.amazonaws.com/bucket',
///       'fields': {'key': 'value'}
///     }
///   }
/// });
/// print(uploadLinks['file1']?.url); // Output: https://s3.amazonaws.com/bucket
/// ```
///
/// - Parameter [json]: A [Map] containing the JSON data.
/// - Returns: A [Map<String, PreSignedUrl>] mapping keys to upload links.
Map<String, PreSignedUrl> parseUploadLinks(Map json) {
  return switch (json) {
    {'mediaUploadLinks': Map raw} => raw.map(
        (key, value) {
          return switch (value) {
            {'url': String url, 'fields': Map fields} => MapEntry(
                key,
                (
                  url: url,
                  fields: fields.map(
                    (key, value) => MapEntry(key.toString(), value.toString()),
                  ),
                ),
              ),
            _ => throw ArgumentError('Incorrect S3 credential data'),
          };
        },
      ),
    _ => throw ArgumentError('Incorrect S3 credential data'),
  };
}


Future<bool> uploadToBucket(PreSignedUrl cred, MultipartFile file) async {
  final PreSignedUrl(:url, :fields) = cred;
  final request = http.MultipartRequest('POST', Uri.parse(url))
    ..fields.addAll(fields)
    ..files.add(
      http.MultipartFile.fromBytes(
        file.$1,
        file.$2,
        filename: file.filename,
        contentType: switch (file.contentType) {
          String contentType => MediaType.parse(contentType),
          null => null,
        },
      ),
    );

  try {
    final response = await request.send();

    switch (response.statusCode) {
      case 204:
        _logger.info('${request.method} on $url: ${response.statusCode}');
        return true;
      case _:
        _logger.warning('${request.method} on $url: ${response.statusCode} - ${await response.stream.bytesToString()}');
        return false;
    }
  } catch (error) {
    _logger.warning('${request.method} on $url: $error');
    return Future.error(error);
  }
}
