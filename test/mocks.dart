import 'package:mockito/annotations.dart';
import 'package:http/http.dart' as http;

@GenerateNiceMocks([
  MockSpec<http.Client>(),
])
// Run with: dart run build_runner build
void main() {}
