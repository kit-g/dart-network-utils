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

  test('nor is a 2xx it could not read: the server may have acted on it', () async {
    expect(await attempts(const NetworkException(statusCode: 201)), 1);
  });

  test('a timeout, a too-early, a throttle and a server error are', () async {
    for (final status in [408, 425, 429, 500, 503]) {
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

  test('retryIf is not asked after the last attempt', () async {
    var asked = 0;
    await expectLater(
      const RetryOptions(maxAttempts: 2, delayFactor: Duration.zero, maxDelay: Duration.zero).retry(
        () => throw const FormatException('x'),
        retryIf: (_) {
          asked++;
          return true;
        },
      ),
      throwsA(isA<FormatException>()),
    );
    expect(asked, 1);
  });

  test('the default rule can be composed into a retryIf', () async {
    expect(retryableByDefault(const NetworkException(statusCode: 409)), isFalse);
    expect(retryableByDefault(const NetworkException(statusCode: 503)), isTrue);
  });
}
