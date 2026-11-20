import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:network_utils/src/requests.dart';
import 'package:test/test.dart';

import 'mocks.mocks.dart';

class TestApi with Requests {
  @override
  final http.Client? client;

  @override
  final String gateway;

  @override
  final Map<String, String>? defaultHeaders;

  TestApi({this.client, this.gateway = 'api.example.com', this.defaultHeaders});
}

class ThrowingApi extends TestApi {
  ThrowingApi({super.client});

  @override
  bool get throwsOnFailure => true;
}

http.Response _resp(String body, int status, String method, Uri url) {
  final req = http.Request(method, url);
  return http.Response(body, status, request: req);
}

void main() {
  group(
    'Requests mixin',
    () {
      late MockClient mock;
      late TestApi api;
      final logs = <LogRecord>[];

      setUpAll(
        () {
          Logger.root.level = Level.ALL;
          Logger.root.onRecord.listen(logs.add);
        },
      );

      setUp(
        () {
          logs.clear();
          mock = MockClient();
          api = TestApi(
            client: mock,
            defaultHeaders: const {'Def': 'D'},
          );
        },
      );

      test(
        'GET: success JSON returns tuple and logs info',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"hello":"world"}', 200, 'GET', url);
            },
          );

          final (json, status) = await api.get(
            '/v1/hello',
            headers: const {'A': '1'},
            query: const {'page': 2, 'flag': true},
          );

          expect(status, 200);
          expect(
            json,
            {'hello': 'world'},
          );

          final captured = verify(mock.get(captureAny, headers: captureAnyNamed('headers'))).captured;
          final Uri calledUrl = captured[0] as Uri;
          final Map<String, String> headers = (captured[1] as Map).cast<String, String>();

          expect(calledUrl.scheme, 'https');
          expect(calledUrl.host, 'api.example.com');
          expect(calledUrl.path, '/v1/hello');
          expect(calledUrl.queryParameters['page'], '2');
          expect(calledUrl.queryParameters['flag'], 'true');

          // defaultHeaders should override per-call on conflicts; here both distinct
          expect(headers, containsPair('A', '1'));
          expect(headers, containsPair('Def', 'D'));

          // Logging
          expect(
              logs.any((r) => r.level == Level.INFO && r.message.toString().contains('GET on /v1/hello: 200')), isTrue);
        },
      );

      test(
        'GET: failure JSON returns tuple and logs shout',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"error":"bad"}', 400, 'GET', url);
            },
          );

          final (json, status) = await api.get('/oops');

          expect(status, 400);
          expect(
            json,
            {'error': 'bad'},
          );
          expect(
              logs.any((r) =>
                  r.level == Level.SHOUT &&
                  r.message.toString().contains('GET on /oops: 400 with payload: {error: bad}')),
              isTrue);
        },
      );

      test(
        'GET: 204 with empty body returns {} and logs info',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('', 204, 'GET', url);
            },
          );

          final (json, status) = await api.get('/no-content');

          expect(status, 204);
          expect(json, isEmpty);
          expect(logs.any((r) => r.level == Level.INFO && r.message.toString().contains('GET on /no-content: 204')),
              isTrue);
        },
      );

      test(
        'GET: 200 with empty body returns {} (treated as empty positive)',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('', 200, 'GET', url);
            },
          );

          final (json, status) = await api.get('/empty');

          expect(status, 200);
          expect(json, isEmpty);
        },
      );

      test(
        'GET: 200 with invalid non-JSON is treated as empty successful response',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('not-json', 200, 'GET', url);
            },
          );

          final (json, status) = await api.get('/bad-json');
          expect(status, 200);
          expect(json, isEmpty);
        },
      );

      test(
        'GET: non-2xx with invalid non-JSON rethrows FormatException',
        () async {
          when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('not-json', 500, 'GET', url);
            },
          );

          expect(() => api.get('/bad-json-500'), throwsA(isA<FormatException>()));
        },
      );

      test(
        'POST: encodes body as JSON and merges headers with defaultHeaders precedence',
        () async {
          when(mock.post(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"ok":true}', 201, 'POST', url);
            },
          );

          final headers = {'X': 'call', 'Def': 'override?'};
          final defHeaders = {'X': 'default', 'Def': 'D'};
          api = TestApi(client: mock, defaultHeaders: defHeaders);

          final body = {'a': 1};
          final (json, status) = await api.post(
            '/things',
            headers: headers,
            body: body,
            query: const {'q': 5},
          );

          expect(status, 201);
          expect(
            json,
            {'ok': true},
          );

          final verified =
              verify(mock.post(captureAny, headers: captureAnyNamed('headers'), body: captureAnyNamed('body')))
                  .captured;
          final Uri url = verified[0] as Uri;
          final Map<String, String> merged = (verified[1] as Map).cast<String, String>();
          final String sentBody = verified[2] as String;

          expect(url.path, '/things');
          expect(url.queryParameters['q'], '5');

          // default headers should take precedence on conflict according to Requests implementation
          expect(merged['X'], 'default');
          expect(merged['Def'], 'D');

          expect(sentBody, jsonEncode(body));
        },
      );

      test(
        'PUT: encodes body as JSON',
        () async {
          when(mock.put(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"updated":true}', 200, 'PUT', url);
            },
          );

          final body = {'name': 'x'};
          final (json, status) = await api.put('/things/1', headers: const {'H': 'V'}, body: body);
          expect(status, 200);
          expect(
            json,
            {'updated': true},
          );

          final captured =
              verify(mock.put(captureAny, headers: captureAnyNamed('headers'), body: captureAnyNamed('body'))).captured;
          final Uri calledUrl = captured[0] as Uri;
          final Map<String, String> headers = (captured[1] as Map).cast<String, String>();
          final String sentBody = captured[2] as String;

          expect(calledUrl.path, '/things/1');
          expect(headers['H'], 'V');
          expect(headers['Def'], 'D');
          expect(sentBody, jsonEncode(body));
        },
      );

      test(
        'PATCH: encodes body as JSON',
        () async {
          when(mock.patch(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"patched":true}', 200, 'PATCH', url);
            },
          );

          final body = {'name': 'x'};
          final (json, status) = await api.patch('/things/1', headers: const {'H': 'V'}, body: body);
          expect(status, 200);
          expect(
            json,
            {'patched': true},
          );

          final captured =
              verify(mock.patch(captureAny, headers: captureAnyNamed('headers'), body: captureAnyNamed('body')))
                  .captured;
          final Uri calledUrl = captured[0] as Uri;
          final Map<String, String> headers = (captured[1] as Map).cast<String, String>();
          final String sentBody = captured[2] as String;

          expect(calledUrl.path, '/things/1');
          expect(headers['H'], 'V');
          expect(headers['Def'], 'D');
          expect(sentBody, jsonEncode(body));
        },
      );

      test(
        'DELETE: builds URL with query and merges headers',
        () async {
          when(mock.delete(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('{"deleted":true}', 200, 'DELETE', url);
            },
          );

          final (json, status) = await api.delete(
            '/things/1',
            headers: const {'Z': 'z'},
            query: const {'force': true},
          );
          expect(status, 200);
          expect(
            json,
            {'deleted': true},
          );

          final captured = verify(mock.delete(captureAny, headers: captureAnyNamed('headers'))).captured;
          final Uri calledUrl = captured[0] as Uri;
          final Map<String, String> headers = (captured[1] as Map).cast<String, String>();

          expect(calledUrl.path, '/things/1');
          expect(calledUrl.queryParameters['force'], 'true');
          expect(headers['Z'], 'z');
          expect(headers['Def'], 'D');
        },
      );

      test(
        'HEAD: builds URL with query and returns {} for 204',
        () async {
          when(mock.head(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('', 204, 'HEAD', url);
            },
          );

          final (json, status) = await api.head(
            '/ping',
            query: const {'t': 1},
          );
          expect(status, 204);
          expect(json, isEmpty);

          final captured = verify(mock.head(captureAny, headers: captureAnyNamed('headers'))).captured;
          final Uri calledUrl = captured[0] as Uri;
          expect(calledUrl.path, '/ping');
          expect(calledUrl.queryParameters['t'], '1');
        },
      );

      test(
        'HEAD: builds URL with query and returns {} for 204',
        () async {
          when(mock.head(any, headers: anyNamed('headers'))).thenAnswer(
            (inv) async {
              final url = inv.positionalArguments.first as Uri;
              return _resp('', 204, 'HEAD', url);
            },
          );

          final (json, status) = await api.head(
            '/ping',
            query: const {'t': 1},
          );
          expect(status, 204);
          expect(json, isEmpty);

          final captured = verify(mock.head(captureAny, headers: captureAnyNamed('headers'))).captured;
          final Uri calledUrl = captured[0] as Uri;
          expect(calledUrl.path, '/ping');
          expect(calledUrl.queryParameters['t'], '1');
        },
      );

      group('onUnauthorized callback', () {
        test(
          '401 response without callback returns original json and status',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"unauthorized"}', 401, 'GET', url);
              },
            );

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'error': 'unauthorized'});
            expect(logs.any((r) => r.level == Level.SHOUT && r.message.toString().contains('GET on /protected: 401')),
                isTrue);
          },
        );

        test(
          '401 response with callback invokes callback and returns its result',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"unauthorized"}', 401, 'GET', url);
              },
            );

            Json? capturedJson;
            api.onUnauthorized = (json) {
              capturedJson = json;
              return ({'handled': true}, 401);
            };

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'handled': true});
            expect(capturedJson, {'error': 'unauthorized'});
          },
        );
      });

      group('onUpgradeRequired callback', () {
        test(
          '426 response without callback returns original json and status',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"upgrade required"}', 426, 'GET', url);
              },
            );

            final (json, status) = await api.get('/versioned');

            expect(status, 426);
            expect(json, {'error': 'upgrade required'});
            expect(logs.any((r) => r.level == Level.SHOUT && r.message.toString().contains('GET on /versioned: 426')),
                isTrue);
          },
        );

        test(
          '426 response with callback invokes callback and returns its result',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"upgrade required","minVersion":"2.0"}', 426, 'GET', url);
              },
            );

            Json? capturedJson;
            api.onUpgradeRequired = (json) {
              capturedJson = json;
              return ({'redirected': true}, 426);
            };

            final (json, status) = await api.get('/versioned');

            expect(status, 426);
            expect(json, {'redirected': true});
            expect(capturedJson, {'error': 'upgrade required', 'minVersion': '2.0'});
          },
        );
      });

      group('onReauthenticate callback', () {
        test(
          '401 with onReauthenticate returning true retries request once',
          () async {
            var callCount = 0;
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                if (callCount == 1) {
                  return _resp('{"error":"unauthorized"}', 401, 'GET', url);
                }
                return _resp('{"data":"success"}', 200, 'GET', url);
              },
            );

            var reauthCalled = false;
            api.onReauthenticate = () async {
              reauthCalled = true;
              return true;
            };

            final (json, status) = await api.get('/protected');

            expect(status, 200);
            expect(json, {'data': 'success'});
            expect(reauthCalled, isTrue);
            expect(callCount, 2);
          },
        );

        test(
          '401 with onReauthenticate returning false does not retry',
          () async {
            var callCount = 0;
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                return _resp('{"error":"unauthorized"}', 401, 'GET', url);
              },
            );

            api.onReauthenticate = () async => false;

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'error': 'unauthorized'});
            expect(callCount, 1);
          },
        );

        test(
          '401 without onReauthenticate does not retry',
          () async {
            var callCount = 0;
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                return _resp('{"error":"unauthorized"}', 401, 'GET', url);
              },
            );

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'error': 'unauthorized'});
            expect(callCount, 1);
          },
        );

        test(
          '401 retry only happens once even if retry also returns 401',
          () async {
            var callCount = 0;
            var reauthCount = 0;
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                return _resp('{"error":"still unauthorized"}', 401, 'GET', url);
              },
            );

            api.onReauthenticate = () async {
              reauthCount++;
              return true;
            };

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'error': 'still unauthorized'});
            expect(callCount, 2); // original + 1 retry
            expect(reauthCount, 1); // only called once
          },
        );

        test(
          'POST 401 with onReauthenticate retries with same body',
          () async {
            var callCount = 0;
            when(mock.post(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                if (callCount == 1) {
                  return _resp('{"error":"unauthorized"}', 401, 'POST', url);
                }
                return _resp('{"created":true}', 201, 'POST', url);
              },
            );

            api.onReauthenticate = () async => true;

            final (json, status) = await api.post('/items', body: {'name': 'test'});

            expect(status, 201);
            expect(json, {'created': true});
            expect(callCount, 2);

            // Verify both calls had the same body
            final captured = verify(
              mock.post(any, headers: anyNamed('headers'), body: captureAnyNamed('body')),
            ).captured;
            expect(captured.length, 2);
            expect(captured[0], captured[1]); // same body on retry
          },
        );

        test(
          'PATCH 401 with onReauthenticate retries with same body',
          () async {
            var callCount = 0;
            when(mock.patch(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                if (callCount == 1) {
                  return _resp('{"error":"unauthorized"}', 401, 'PATCH', url);
                }
                return _resp('{"patched":true}', 200, 'PATCH', url);
              },
            );

            api.onReauthenticate = () async => true;

            final (json, status) = await api.patch('/items/1', body: {'name': 'test'});

            expect(status, 200);
            expect(json, {'patched': true});
            expect(callCount, 2);

            // Verify both calls had the same body
            final captured = verify(
              mock.patch(any, headers: anyNamed('headers'), body: captureAnyNamed('body')),
            ).captured;
            expect(captured.length, 2);
            expect(captured[0], captured[1]); // same body on retry
          },
        );

        test(
          'non-401 status does not trigger onReauthenticate',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"forbidden"}', 403, 'GET', url);
              },
            );

            var reauthCalled = false;
            api.onReauthenticate = () async {
              reauthCalled = true;
              return true;
            };

            final (json, status) = await api.get('/forbidden');

            expect(status, 403);
            expect(json, {'error': 'forbidden'});
            expect(reauthCalled, isFalse);
          },
        );

        test(
          'onUnauthorized is still called if onReauthenticate fails',
          () async {
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                return _resp('{"error":"unauthorized"}', 401, 'GET', url);
              },
            );

            api.onReauthenticate = () async => false;

            Json? capturedJson;
            api.onUnauthorized = (json) {
              capturedJson = json;
              return ({'handled': true}, 401);
            };

            final (json, status) = await api.get('/protected');

            expect(status, 401);
            expect(json, {'handled': true});
            expect(capturedJson, {'error': 'unauthorized'});
          },
        );

        test(
          'retry after reauth sends refreshed defaultHeaders, not a stale snapshot',
          () async {
            // A mutable auth header that reauth rotates in place, mirroring how a
            // real client swaps a refreshed token into defaultHeaders.
            final headers = <String, String>{'Authorization': 'Bearer old'};
            final localApi = TestApi(client: mock, defaultHeaders: headers);

            final sentTokens = <String?>[];
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                final sent = (inv.namedArguments[#headers] as Map)['Authorization'] as String?;
                sentTokens.add(sent);
                return switch (sent) {
                  'Bearer new' => _resp('{"data":"ok"}', 200, 'GET', url),
                  _ => _resp('{"error":"unauthorized"}', 401, 'GET', url),
                };
              },
            );

            localApi.onReauthenticate = () async {
              headers['Authorization'] = 'Bearer new';
              return true;
            };

            final (json, status) = await localApi.get('/protected');

            expect(status, 200);
            expect(json, {'data': 'ok'});
            // The first attempt used the stale token; the retry must carry the
            // refreshed one rather than a snapshot taken before reauth.
            expect(sentTokens, ['Bearer old', 'Bearer new']);
          },
        );

        test(
          'blank body on a failed retry surfaces NetworkException, not FormatException',
          () async {
            var callCount = 0;
            when(mock.get(any, headers: anyNamed('headers'))).thenAnswer(
              (inv) async {
                final url = inv.positionalArguments.first as Uri;
                callCount++;
                // The first 401 carries a body; the retry comes back a bare 401.
                return switch (callCount) {
                  1 => _resp('{"error":"unauthorized"}', 401, 'GET', url),
                  _ => _resp('', 401, 'GET', url),
                };
              },
            );

            api.onReauthenticate = () async => true;

            await expectLater(api.get('/protected'), throwsA(isA<NetworkException>()));
            expect(callCount, 2);
          },
        );
      });
    },
  );

  group('throwsOnFailure', () {
    late MockClient mock;
    late ThrowingApi api;

    setUp(() {
      mock = MockClient();
      api = ThrowingApi(client: mock);
    });

    void answer(String body, int status) {
      when(mock.put(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer(
        (inv) async => _resp(body, status, 'PUT', inv.positionalArguments.first as Uri),
      );
    }

    test('a failure with a body is thrown with its body, verb and path', () async {
      answer('{"code":"name_taken"}', 409);
      await expectLater(
        api.put('/v1/exercises/aB3dE5fG7hI9jK1lM3nO5pQ7rS9t', body: const {}),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.body, 'body', {'code': 'name_taken'})
              .having((e) => e.method, 'method', 'PUT')
              .having((e) => e.toString(), 'toString', 'NetworkException(409 PUT /v1/exercises/{id})'),
        ),
      );
    });

    test('a success is still returned', () async {
      answer('{"ok":true}', 200);
      final (json, status) = await api.put('/v1/exercises/1', body: const {});
      expect(json, {'ok': true});
      expect(status, 200);
    });

    test('a 426 goes to its callback, and what it answers is thrown unless a success', () async {
      answer('{"error":"upgrade required"}', 426);
      Json? seen;
      api.onUpgradeRequired = (json) {
        seen = json;
        return (json, 426);
      };
      await expectLater(
        api.put('/v1/accounts', body: const {}),
        throwsA(isA<NetworkException>().having((e) => e.body, 'body', {'error': 'upgrade required'})),
      );
      expect(seen, {'error': 'upgrade required'});

      api.onUpgradeRequired = (json) => ({'handled': true}, 200);
      final (json, _) = await api.put('/v1/accounts', body: const {});
      expect(json, {'handled': true});
    });

    test('a bare 426 still reaches its callback', () async {
      answer('', 426);
      var called = false;
      api.onUpgradeRequired = (json) {
        called = true;
        return (json, 426);
      };
      await expectLater(api.put('/v1/accounts', body: const {}), throwsA(isA<NetworkException>()));
      expect(called, isTrue);
    });

    test('a 401 with its callback set goes to the callback', () async {
      answer('{"message":"Unauthorized"}', 401);
      var called = false;
      api.onUnauthorized = (json) {
        called = true;
        return (json, 401);
      };
      await expectLater(
        api.put('/v1/accounts', body: const {}),
        throwsA(isA<NetworkException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(called, isTrue);
    });

    test('a 401 that reauthenticates is sent again, and its answer returned', () async {
      var calls = 0;
      when(mock.put(any, headers: anyNamed('headers'), body: anyNamed('body'))).thenAnswer((inv) async {
        calls++;
        final url = inv.positionalArguments.first as Uri;
        return calls == 1 ? _resp('{"message":"expired"}', 401, 'PUT', url) : _resp('{"ok":true}', 200, 'PUT', url);
      });
      api.onReauthenticate = () async => true;
      final (json, status) = await api.put('/v1/accounts', body: const {});
      expect(json, {'ok': true});
      expect(status, 200);
      expect(calls, 2);
    });

    test('an HTML or plain-text error page is thrown as a failure, without its text', () async {
      answer('<html>Bad Gateway</html>', 502);
      await expectLater(
        api.put('/v1/accounts', body: const {}),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.body, 'body', isNull)
              .having((e) => e.toString(), 'toString', 'NetworkException(502 PUT /v1/accounts)'),
        ),
      );
    });

    test('an HTML 426 and a non-object 401 still reach their callbacks', () async {
      answer('<html>Upgrade Required</html>', 426);
      Json? seen;
      api.onUpgradeRequired = (json) {
        seen = json;
        return (json, 426);
      };
      await expectLater(api.put('/x', body: const {}), throwsA(isA<NetworkException>()));
      expect(seen, <String, dynamic>{});

      answer('"unauthorized"', 401);
      var called = false;
      api.onUnauthorized = (json) {
        called = true;
        return (json, 401);
      };
      await expectLater(api.put('/x', body: const {}), throwsA(isA<NetworkException>()));
      expect(called, isTrue);
    });

    test("what a callback throws is the callback's, not a parse failure", () async {
      answer('{"min":"2.0"}', 426);
      api.onUpgradeRequired = (json) => (json, int.parse(json['min'] as String));
      await expectLater(api.put('/x', body: const {}), throwsA(isA<FormatException>()));
    });

    test("the thrown status and body are the server's, whatever the callback answers", () async {
      answer('{"message":"expired"}', 401);
      api.onUnauthorized = (json) => (<String, dynamic>{}, 500);
      await expectLater(
        api.put('/x', body: const {}),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.body, 'body', {'message': 'expired'}),
        ),
      );
    });

    test('a 2xx cut short is thrown without its body', () async {
      answer('{"email":"muffin@example.com", ', 200);
      await expectLater(
        api.put('/x', body: const {}),
        throwsA(isA<NetworkException>().having((e) => e.body, 'body', isNull)),
      );
    });

    test('the exception keeps the raw path; only its message is templated', () async {
      answer('{"code":"gone"}', 404);
      await expectLater(
        api.put('/v1/workouts/aB3dE5fG7hI9jK1lM3nO5pQ7rS9t', body: const {}),
        throwsA(isA<NetworkException>().having((e) => e.path, 'path', '/v1/workouts/aB3dE5fG7hI9jK1lM3nO5pQ7rS9t')),
      );
    });

    test('a 401 with no callback is thrown like any other failure', () async {
      answer('{"message":"Unauthorized"}', 401);
      await expectLater(
        api.put('/v1/accounts', body: const {}),
        throwsA(isA<NetworkException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('off, a bare 426 is thrown and its callback not called, as before', () async {
      final plain = TestApi(client: mock);
      answer('', 426);
      var called = false;
      plain.onUpgradeRequired = (json) {
        called = true;
        return (json, 426);
      };
      await expectLater(plain.put('/x', body: const {}), throwsA(isA<NetworkException>()));
      expect(called, isFalse);
    });

    test('off by default: the record comes back', () async {
      final plain = TestApi(client: mock);
      answer('{"code":"name_taken"}', 409);
      final (json, status) = await plain.put('/v1/exercises/1', body: const {});
      expect(json, {'code': 'name_taken'});
      expect(status, 409);
    });
  });

  group('NetworkException', () {
    test('timestamp ids are templated', () {
      const e = NetworkException(statusCode: 500, method: 'PUT', path: '/v1/workouts/2024-03-05T18:22:11.123Z');
      expect(e.toString(), 'NetworkException(500 PUT /v1/workouts/{id})');
      for (final id in [
        '2024-03-05T18:22:11+02:00',
        '2024-03-05T18:22:11+02',
        '2024-03-05t18:22:11z',
        '2024-03-05T18:22:11,5Z',
        '2024-03-05',
        '2024-03-05%2018:22:11.123',
        '2024-03-05T18',
        '2024-03-05T18Z',
        '2024-03-05T182211Z',
      ]) {
        expect(NetworkException(statusCode: 500, path: '/v1/workouts/$id/sets').endpoint, '/v1/workouts/{id}/sets',
            reason: id);
      }
    });

    test('names status, verb and endpoint, with identifiers templated', () {
      const e = NetworkException(
        statusCode: 401,
        method: 'GET',
        path: '/v1/accounts/aB3dE5fG7hI9jK1lM3nO5pQ7rS9t/workouts/0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b',
      );
      expect(e.toString(), 'NetworkException(401 GET /v1/accounts/{id}/workouts/{id})');
    });

    test('keeps the body out of the message', () {
      const e = NetworkException(statusCode: 400, body: {'email': 'muffin@example.com'});
      expect(e.toString(), 'NetworkException(400)');
    });

    test('route words and numeric ids', () {
      const e = NetworkException(statusCode: 404, method: 'DELETE', path: '/v1/template-folders/42');
      expect(e.endpoint, '/v1/template-folders/{id}');
    });
  });
}
