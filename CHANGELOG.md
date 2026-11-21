## 0.7.0

- `Requests.failure(NetworkException) → Exception`: what a `NetworkException`
  is thrown as, the exception itself by default. Every `NetworkException` the
  library throws goes through it, after the 401/426 callback has run and not
  answered with a 2xx. With `throwsOnFailure` on, that is every failure,
  error pages that aren't JSON and unreadable 2xx included; off, a JSON
  failure still comes back as a record and a non-JSON page still throws its
  `FormatException`. Override it to throw a domain type (a named refusal, a
  forced upgrade) in one place instead of catching around every call. It is
  thrown where the failure happened, so the trace is the request's.
- `originOf(Object)`: the `NetworkException` a mapped exception came from.
  `retryableByDefault` reads it, so a refusal turned into a domain type is
  still not asked again, and a 5xx still is.
- Breaking for a class that mixes in `Requests` and already has a member
  named `failure`, or that implements `Requests` without `noSuchMethod`.
  Nothing else changes for a client that doesn't override it.

## 0.6.0

With `throwsOnFailure` on:
- Every failure is thrown, so a returned value always means success. An HTML
  or plain-text error page, and a 2xx whose body can't be read, are thrown as
  a `NetworkException` with status, verb and path and no body, so no body
  reaches a message.
- A 401 or 426 goes to its callback whatever its body (`{}` when it isn't a
  JSON object). The failure is thrown, with the server's own status and body,
  unless the callback answers with a 2xx.
- Something a callback throws reaches the caller as itself.

Always:
- `retry()` with no `retryIf` asks again only for what `retryableByDefault`
  allows: not a `NetworkException` unless it `isTransient` (408, 425, 429 or
  5xx). A refusal, or a 2xx the client couldn't read, is not repeated.
  Behaviour change: a 404 or 409 that used to be retried isn't.
- `retryIf` is no longer asked after the last attempt.
- `endpoint` templates more date and timestamp forms: lowercase `t`/`z`, hour
  or basic times (`T18`, `T182211Z`), an hour-only offset, a comma before the
  fraction, a bare date, and an encoded space separator.

## 0.5.0

- `Requests.throwsOnFailure` (off by default): a failed response with a JSON
  body is thrown as a `NetworkException` carrying its `body`, `method` and
  `path`, instead of being returned as a record. A 401 or 426 with its
  callback set still goes to the callback.
- `NetworkException.endpoint` templates ISO-8601 timestamp segments to `{id}`.

## 0.4.5

- `NetworkException` carries the request's `method` and `path`, and its
  `toString` names them: `NetworkException(401 GET /v1/accounts/{id}/workouts)`.
  Identifier-like path segments are templated; the body is never included.

## 1.0.0

- Initial version.
