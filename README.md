## Overview

This package provides a set of reusable utilities for working with HTTP requests and Amazon S3 in Dart/Flutter projects.
It includes mixins and helper methods to simplify API interactions and S3 uploads, handle API responses, and streamline
common patterns in network-based development.

## Features

- **HTTP Utilities**:
    - A mixin for making `GET`, `POST`, `PUT`, and `DELETE` requests.
    - Built-in support for JSON serialization and query parameter handling.
    - Automatic logging of success and failure responses.
    - Customizable API gateways and default headers for streamlined configuration.

- **S3 Utilities**:
    - Parse pre-signed URLs and credentials from JSON responses.
    - Upload files to S3 buckets with multi-part form data.
    - Type-safe and flexible handling of file metadata (e.g., filename, content type).
    - Handles edge cases and provides meaningful error handling.

## Installation

To use this package, add it to your `pubspec.yaml`:

```yaml
dependencies:
  network_utils:
    git:
      url: "https://github.com/kit-g/dart-network-utils.git"
```

Then, run `flutter pub get` or `dart pub get` to install the dependency.

## Usage

### HTTP Client

The `Requests` mixin simplifies HTTP request handling. Example usage:

```dart
import 'package:your_package_name/requests.dart';

class MyApiClient with Requests {
  @override
  String get gateway => 'api.example.com'; // Your API base URL

  @override
  Map<String, String>? get defaultHeaders =>
      {
        'Authorization': 'Bearer <your_token>',
        'Content-Type': 'application/json',
      };
}

void main() async {
  final client = MyApiClient();

  try {
    // Sending a GET request
    final response = await client.get('/endpoint');
    print('Response Data: ${response.$1}, Status Code: ${response.$2}');
  } catch (e) {
    print('Error: $e');
  }
}
```

---

### S3 Helper Functions

Simplify S3 file uploads with `parseUploadLinks` and `uploadToBucket`.
**Parsing Pre-signed URLs**

```dart
import 'package:your_package_name/s3.dart';

void main() {
  final uploadLinks = parseUploadLinks({
    'mediaUploadLinks': {
      'file1': {
        'url': 'https://s3.amazonaws.com/bucket',
        'fields': {'key': 'value'}
      }
    }
  });

  print(uploadLinks['file1']?.url); // Output: https://s3.amazonaws.com/bucket
}
```

**Uploading Files to S3**

```dart
import 'package:your_package_name/s3.dart';

void main() async {
  final s3Credential = (
  url: 'https://s3.amazonaws.com/bucket',
  fields: {'key': 'value'}
  );

  final file = (
  'file',
  [ /* File Bytes */
  ],
  filename: 'example.txt',
  contentType: 'text/plain',
  );

  try {
    final success = await uploadToBucket(s3Credential, file);
    print(success ? 'Upload successful' : 'Upload failed');
  } catch (e) {
    print('Error during upload: $e');
  }
}
```

**Key Features**:

- `parseUploadLinks`: Extracts pre-signed URLs and fields from JSON responses.
- `uploadToBucket`: Handles uploading files using the extracted credentials.

## Benefits

1. **Ease of Use**: Gain access to pre-built abstractions for HTTP requests and S3 uploads, reducing boilerplate code.
2. **Compatibility**: Fully compatible with Dart and Flutter projects.
3. **Extensibility**: Both the HTTP and S3 utilities are designed to be extended for custom use cases.
4. **Logging**: Integrated logging with support for both info and error messages to simplify debugging.

## Future Improvements

- **Additional HTTP Verb Support**: Add support for PATCH/HEAD/OPTIONS requests.
- **Retry Mechanism**: Support for automatically retrying failed requests with exponential backoff.
- **Streamed Uploads**: Add options for uploading large files in chunks.
- **More S3 Integrations**: Provide additional abstractions for S3-specific API operations beyond uploading.

## Contributions

Contributions are welcome! Feel free to open issues or submit pull requests to improve the package. Before submitting a
PR, please ensure all code passes tests and adheres to Dart style guidelines.

## License

This package is licensed under the MIT License. See the `LICENSE` file for more information.
