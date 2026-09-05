import 'dart:convert';

/// Result of parsing a Shelly QR code or barcode payload.
class ShellyQrParseResult {
  const ShellyQrParseResult({
    required this.deviceId,
    this.cloudHost,
    this.model,
    this.lanAddress,
    this.rawText,
  });

  final String deviceId;
  final String? cloudHost;
  final String? model;
  final String? lanAddress;
  final String? rawText;

  @override
  String toString() =>
      'ShellyQrParseResult(deviceId: $deviceId, cloudHost: $cloudHost, model: $model, lanAddress: $lanAddress)';
}

/// Helper parser to extract device ID, cloud host, and model from QR codes or text
/// found on Shelly devices, packaging, or the Shelly app.
class ShellyQrParser {
  const ShellyQrParser._();

  /// Parses a raw string scanned from a QR code or barcode.
  /// Returns null if no recognizable Shelly identifier is found.
  static ShellyQrParseResult? parse(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) return null;

    // 1. Check if it's a JSON payload (exported from Shelly app or config)
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final map = jsonDecode(text);
        if (map is Map<String, dynamic>) {
          final id = map['id']?.toString() ??
              map['deviceId']?.toString() ??
              map['device_id']?.toString();
          if (id != null && id.isNotEmpty) {
            return ShellyQrParseResult(
              deviceId: id.trim(),
              cloudHost: map['cloud_host']?.toString() ?? map['server']?.toString(),
              model: map['model']?.toString() ?? map['type']?.toString(),
              lanAddress: map['ip']?.toString() ?? map['lan']?.toString(),
              rawText: text,
            );
          }
        }
      } catch (_) {}
    }

    // 2. Check if it's an HTTP/HTTPS URL
    if (text.startsWith('http://') || text.startsWith('https://')) {
      try {
        final uri = Uri.parse(text);
        
        // Query param id or device_id: e.g. https://shelly-api-eu.shelly.cloud/?id=shellyplugs3-c049ef87b64c
        final qId = uri.queryParameters['id'] ??
            uri.queryParameters['device_id'] ??
            uri.queryParameters['deviceId'];
        if (qId != null && qId.isNotEmpty) {
          final host = uri.host.contains('shelly.cloud')
              ? '${uri.scheme}://${uri.host}'
              : null;
          return ShellyQrParseResult(
            deviceId: qId.trim(),
            cloudHost: host,
            model: _inferModel(qId),
            rawText: text,
          );
        }

        // URL path containing device id
        final pathSegments = uri.pathSegments;
        for (final seg in pathSegments) {
          if (_isShellyDeviceId(seg)) {
            return ShellyQrParseResult(
              deviceId: seg.trim(),
              cloudHost: uri.host.contains('shelly.cloud')
                  ? '${uri.scheme}://${uri.host}'
                  : null,
              model: _inferModel(seg),
              rawText: text,
            );
          }
        }
      } catch (_) {}
    }

    // 3. Check for standard Shelly device ID patterns:
    // e.g. "shellyplugs3-c049ef87b64c", "shellyplus1-xxxxxxxxxxxx", "shellyplugus-xxxxxx"
    final deviceIdRegex = RegExp(
      r'(shelly[a-z0-9_-]+)',
      caseSensitive: false,
    );
    final match = deviceIdRegex.firstMatch(text);
    if (match != null) {
      final id = match.group(1)!.trim();
      return ShellyQrParseResult(
        deviceId: id,
        model: _inferModel(id),
        rawText: text,
      );
    }

    // 4. Check for MAC address format (common on device labels: "C0:49:EF:87:B6:4C" or "c049ef87b64c")
    final macFormattedRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    if (macFormattedRegex.hasMatch(text)) {
      final cleanMac = text.replaceAll(':', '').replaceAll('-', '').toLowerCase();
      return ShellyQrParseResult(
        deviceId: 'shellyplugs3-$cleanMac',
        model: 'Shelly Plug S Gen3',
        rawText: text,
      );
    }

    final rawHex12Regex = RegExp(r'^[0-9A-Fa-f]{12}$');
    if (rawHex12Regex.hasMatch(text)) {
      final cleanMac = text.toLowerCase();
      return ShellyQrParseResult(
        deviceId: 'shellyplugs3-$cleanMac',
        model: 'Shelly Plug S Gen3',
        rawText: text,
      );
    }

    // Fallback: If text has at least 6 alphanumeric characters without spaces
    if (RegExp(r'^[A-Za-z0-9_-]{6,32}$').hasMatch(text)) {
      return ShellyQrParseResult(
        deviceId: text,
        model: _inferModel(text),
        rawText: text,
      );
    }

    return null;
  }

  static bool _isShellyDeviceId(String str) {
    final lower = str.toLowerCase();
    return lower.startsWith('shelly') && lower.length >= 8;
  }

  static String? _inferModel(String deviceId) {
    final lower = deviceId.toLowerCase();
    if (lower.contains('plugs3') || lower.contains('plug-s-g3')) {
      return 'Shelly Plug S Gen3';
    } else if (lower.contains('plugs')) {
      return 'Shelly Plug S';
    } else if (lower.contains('plus1')) {
      return 'Shelly Plus 1';
    } else if (lower.contains('pluspm')) {
      return 'Shelly Plus PM';
    } else if (lower.contains('pro')) {
      return 'Shelly Pro';
    }
    return null;
  }
}
