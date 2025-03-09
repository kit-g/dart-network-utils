import 'package:network_utils/network_utils.dart';

class MyApiClient with Requests {
  @override
  String get gateway => 'api.example.com';

  @override
  Map<String, String>? get defaultHeaders {
    return {
      'Authorization': 'Bearer <your_token_here>',
      'Content-Type': 'application/json',
    };
  }
}

Future<void> main() async {
  final client = MyApiClient();

  try {
    final response = await client.get('/endpoint');
    print('Response Data: ${response.$1}, Status Code: ${response.$2}');
  } catch (e) {
    print('Error: $e');
  }
}
