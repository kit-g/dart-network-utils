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
      });
    },
  );
}
