import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:logging/logging.dart';

final _logger = Logger('S3');

typedef MultipartFile = (String field, List<int> value, {String? filename, String? contentType});
typedef PreSignedUrl = ({String url, Map<String, String> fields});

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
