import 'failure.dart';

sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);
  final Failure failure;
}
