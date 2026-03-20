sealed class Hot100Failure {
  final String message;
  const Hot100Failure(this.message);
}

class NetworkFailure extends Hot100Failure {
  const NetworkFailure(super.message);
}

class ServerFailure extends Hot100Failure {
  const ServerFailure(super.message);
}

class ParseFailure extends Hot100Failure {
  const ParseFailure(super.message);
}
