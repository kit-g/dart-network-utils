## 0.5.1

With `throwsOnFailure` on:
- An HTML or plain-text error page is thrown as a `NetworkException` (status,
  verb, path, no body) instead of a `FormatException` carrying the page.
- A 401 or 426 goes to its callback even with an empty body, and whatever the
  callback answers is thrown unless it is a success, so a returned record
  always means the request succeeded.

Always:
- `retry()` with no `retryIf` no longer repeats a `NetworkException` refusal
  (a 4xx other than 408 or 429).
- `endpoint` templates more date and timestamp forms: lowercase `t`/`z`, an
  hour-only offset, a comma before the fraction, a bare date, and an encoded
  space separator.

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
