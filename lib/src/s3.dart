import 'dart:async';

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

/// Uploads a file to an S3 bucket using pre-signed URL credentials.
///
/// This function sends a multipart `POST` request to the specified URL using the form fields
/// and file data defined in the provided [cred] and [file]. It is designed to work with
/// pre-signed URLs typically generated for AWS S3 or compatible storage systems.
///
/// The function logs the response status, indicating success for HTTP 204 or providing detailed error
/// messages upon failure.
///
/// ### Example:
/// ```dart
/// final result = await uploadToBucket(
///   (url: 'https://example-bucket.s3.amazonaws.com', fields: {'key': 'fileKey'}),
///   ('fileField', [104, 105, 106], filename: 'example.txt', contentType: 'text/plain'),
/// );
/// if (result) {
///   print('File uploaded successfully');
/// } else {
///   print('Upload failed');
/// }
/// ```
///
/// ### Parameters:
/// - **[cred]**: A [PreSignedUrl] containing the:
///   - `url`: The pre-signed URL for the upload endpoint.
///   - `fields`: The required form fields for the upload request.
/// - **[file]**: A [MultipartFile] that represents:
///   - `field`: The field name for the uploaded file.
///   - `value`: The file content in bytes.
///   - `filename` (Optional): The file's name on upload.
///   - `contentType` (Optional): The MIME type of the file, such as `application/pdf` or `image/png`.
///
/// ### Returns:
/// - A `Future<bool>`:
///   - `true` if the upload is successful (HTTP status code 204).
///   - `false` for any other status code indicating failure.
///
/// ### Throws:
/// - A `Future.error` if an exception occurs during the HTTP request, such as a network error.
Future<bool> uploadToBucket(
  PreSignedUrl cred,
  MultipartFile file, {
  final void Function(int bytes, int totalBytes)? onProgress,
}) async {
  final PreSignedUrl(:url, :fields) = cred;
  final request = MultipartRequest('POST', Uri.parse(url), onProgress: onProgress)
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

/// Thanks to
/// https://gist.github.com/orestesgaolin/69c112893532e1dd0e8fe01cb07ffc86
class MultipartRequest extends http.MultipartRequest {
  final void Function(int bytes, int totalBytes)? onProgress;

  MultipartRequest(
    super.method,
    super.url, {
    this.onProgress,
  });

  /// Freezes all mutable fields and returns a
  /// single-subscription [http.ByteStream]
  /// that will emit the request body.
  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;

    final total = contentLength;
    var bytes = 0;

    final t = StreamTransformer.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytes += data.length;
        onProgress?.call(bytes, total);
        sink.add(data);
      },
    );
    final stream = byteStream.transform(t);
    return http.ByteStream(stream);
  }
}
