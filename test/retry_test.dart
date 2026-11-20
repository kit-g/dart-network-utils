import 'package:network_utils/network_utils.dart';
import 'package:test/test.dart';

void main() {
  const quick = RetryOptions(maxAttempts: 3, delayFactor: Duration.zero, maxDelay: Duration.zero);

  Future<int> attempts(Exception failure) async {
    var calls = 0;
    await expectLater(
      quick.retry(() {
        calls++;
        throw failure;
      }),
      throwsA(same(failure)),
    );
    return calls;
  }

  test('a 4xx refusal is not asked again', () async {
    expect(await attempts(const NetworkException(statusCode: 409, body: {'code': 'name_taken'})), 1);
  });

  test('a timeout, a throttle and a server error are', () async {
    for (final status in [408, 429, 500, 503]) {
      expect(await attempts(NetworkException(statusCode: status)), 3, reason: '$status');
    }
  });

  test('any other exception is, as before', () async {
    expect(await attempts(const FormatException('x')), 3);
  });

  test('a retryIf given still decides', () async {
    var calls = 0;
    await expectLater(
      quick.retry(() {
        calls++;
        throw const NetworkException(statusCode: 409);
      }, retryIf: (_) => true),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, 3);
  });
}
