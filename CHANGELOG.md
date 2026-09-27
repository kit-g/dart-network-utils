## 0.4.5

- `NetworkException` carries the request's `method` and `path`, and its
  `toString` names them: `NetworkException(401 GET /v1/accounts/{id}/workouts)`.
  Identifier-like path segments are templated; the body is never included.

## 1.0.0

- Initial version.
