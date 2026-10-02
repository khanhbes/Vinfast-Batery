import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'smart_charger_service.dart';

/// One attempt only. In particular, a transport failure must never retry ON.
class ShellyApiTransport {
  static Future<http.Response> send(
    http.Client client,
    http.Request request, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      // Include response-body consumption in the deadline, not only headers.
      return await (() async {
        final stream = await client.send(request);
        return http.Response.fromStream(stream);
      })().timeout(timeout);
    } on Object catch (error) {
      final ambiguous = request.method != 'GET' && request.method != 'HEAD';
      final tls =
          error is HandshakeException ||
          error is TlsException ||
          (error is http.ClientException &&
              RegExp(
                r'HandshakeException|CERTIFICATE_VERIFY_FAILED|TLS',
                caseSensitive: false,
              ).hasMatch(error.message));
      throw SmartChargerException(
        tls
            ? 'Không thể thiết lập kết nối bảo mật. Vui lòng thử lại sau.'
            : error is TimeoutException
            ? 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.'
            : 'Không thể kết nối máy chủ. Kiểm tra mạng rồi thử lại.',
        code: tls
            ? 'tls_failed'
            : error is TimeoutException
            ? 'timeout'
            : 'connection_failed',
        statusCode: error is TimeoutException ? 504 : 503,
        retryable: !tls,
        commandMayHaveReachedDevice: ambiguous,
      );
    }
  }
}
