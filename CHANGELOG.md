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
