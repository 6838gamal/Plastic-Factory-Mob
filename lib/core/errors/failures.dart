abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure() : super('لا يوجد اتصال بالإنترنت، سيتم الحفظ محلياً');
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class InsufficientStockFailure extends Failure {
  final String materialName;
  final double required;
  final double available;
  const InsufficientStockFailure({
    required this.materialName,
    required this.required,
    required this.available,
  }) : super('الكمية المطلوبة من $materialName ($required كجم) أكبر من المتوفر ($available كجم)');
}

class DuplicateTransactionFailure extends Failure {
  const DuplicateTransactionFailure() : super('عملية مكررة، تم منع التنفيذ');
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}
