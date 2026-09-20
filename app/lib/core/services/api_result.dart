/// Typed result envelope shared by user-facing API flows.
///
/// The legacy ApiService map methods remain available while callers migrate;
/// this type prevents raw exceptions and response bodies leaking into release
/// UI and carries retry semantics for the sync queue.
class ApiResult<T> {
  const ApiResult({
    required this.success,
    this.data,
    this.code,
    this.userMessage,
    this.retryable = false,
    this.requestId,
    this.httpStatus,
  });

  final bool success;
  final T? data;
  final String? code;
  final String? userMessage;
  final bool retryable;
  final String? requestId;
  final int? httpStatus;

  factory ApiResult.fromMap(
    Map<String, dynamic> map, {
    T? Function(dynamic value)? decode,
  }) {
    final ok = map['success'] == true;
    return ApiResult<T>(
      success: ok,
      data: ok ? decode?.call(map['data']) : null,
      code: map['code']?.toString(),
      userMessage: map['userMessage']?.toString() ?? map['error']?.toString(),
      retryable: map['retryable'] == true,
      requestId: map['requestId']?.toString(),
      httpStatus: map['statusCode'] is num
          ? (map['statusCode'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toLegacyMap() => {
        'success': success,
        if (data != null) 'data': data,
        if (code != null) 'code': code,
        if (userMessage != null) ...{
          'userMessage': userMessage,
          'error': userMessage,
        },
        'retryable': retryable,
        if (requestId != null) 'requestId': requestId,
        if (httpStatus != null) 'statusCode': httpStatus,
      };
}

