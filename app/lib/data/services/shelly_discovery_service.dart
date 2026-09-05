import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import '../models/shelly_connection.dart';

class ShellyDiscoveryService {
  const ShellyDiscoveryService();

  Future<List<DiscoveredShellyDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (
            dynamic host,
            int port, {
            bool? reuseAddress,
            bool? reusePort,
            int? ttl,
          }) => RawDatagramSocket.bind(
            host,
            port,
            reuseAddress: true,
            reusePort: false,
            ttl: ttl ?? 1,
          ),
    );
    final devices = <String, DiscoveredShellyDevice>{};
    try {
      await client.start();
      final pointers = client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_shelly._tcp.local'),
          )
          .timeout(timeout);
      await for (final pointer in pointers) {
        final services = client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(pointer.domainName),
        );
        await for (final service in services) {
          String address = service.target;
          final ips = client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(service.target),
          );
          await for (final ip in ips) {
            address = ip.address.address;
            break;
          }
          final txt = <String, String>{};
          final records = client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(pointer.domainName),
          );
          await for (final record in records) {
            for (final item in record.text.split(RegExp(r'\s+'))) {
              final separator = item.indexOf('=');
              if (separator > 0) {
                txt[item.substring(0, separator).toLowerCase()] = item
                    .substring(separator + 1);
              }
            }
          }
          final id = txt['id'] ?? pointer.domainName.split('.').first;
          final model = txt['app'] ?? txt['model'] ?? '';
          final generation = int.tryParse(txt['gen'] ?? '');
          final device = DiscoveredShellyDevice(
            id: id,
            address: address,
            model: model,
            name: pointer.domainName.split('.').first,
            generation: generation,
          );
          if (device.isPlugSGen3) devices[id] = device;
        }
      }
    } catch (_) {
      // Gracefully handle timeout or platform mDNS/multicast restrictions
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
    return devices.values.toList(growable: false);
  }

  /// Probes an individual device via LAN HTTP to get firmware, auth state, and telemetry.
  Future<DiscoveredShellyDevice> probeDevice(
    DiscoveredShellyDevice device, {
    Duration timeout = const Duration(seconds: 3),
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    String? firmware = device.firmware;
    bool authEnabled = device.authEnabled;
    double? currentPowerW = device.currentPowerW;
    bool? relayState = device.relayState;
    double? temperatureC = device.temperatureC;
    String? name = device.name;
    String model = device.model;

    try {
      final baseUri = Uri.parse('http://${device.address}');

      // 1. Probe Device Info (/shelly or /rpc/Shelly.GetDeviceInfo)
      try {
        final infoUri = baseUri.replace(path: '/rpc/Shelly.GetDeviceInfo');
        final infoRes = await client.get(infoUri).timeout(timeout);
        if (infoRes.statusCode == 200) {
          final data = jsonDecode(infoRes.body);
          if (data is Map<String, dynamic>) {
            firmware = data['ver']?.toString() ?? data['fw_id']?.toString();
            authEnabled = data['auth_en'] == true;
            if (data['app'] != null) model = data['app'].toString();
            if (data['name'] != null && data['name'].toString().isNotEmpty) {
              name = data['name'].toString();
            }
          }
        } else if (infoRes.statusCode == 401) {
          authEnabled = true;
        }
      } catch (_) {
        // Fallback to /shelly
        try {
          final legacyUri = baseUri.replace(path: '/shelly');
          final legacyRes = await client.get(legacyUri).timeout(timeout);
          if (legacyRes.statusCode == 200) {
            final data = jsonDecode(legacyRes.body);
            if (data is Map<String, dynamic>) {
              firmware = data['ver']?.toString() ?? data['fw_id']?.toString();
              authEnabled = data['auth_en'] == true;
              if (data['name'] != null && data['name'].toString().isNotEmpty) {
                name = data['name'].toString();
              }
            }
          } else if (legacyRes.statusCode == 401) {
            authEnabled = true;
          }
        } catch (_) {}
      }

      // 2. Probe Status if not password protected
      if (!authEnabled) {
        try {
          final statusUri = baseUri.replace(path: '/rpc/Shelly.GetStatus');
          final statusRes = await client.get(statusUri).timeout(timeout);
          if (statusRes.statusCode == 200) {
            final data = jsonDecode(statusRes.body);
            if (data is Map<String, dynamic>) {
              final sw = data['switch:0'];
              if (sw is Map<String, dynamic>) {
                relayState = sw['output'] == true;
                currentPowerW = (sw['apower'] as num?)?.toDouble();
                final temp = sw['temperature'];
                if (temp is Map<String, dynamic>) {
                  temperatureC = (temp['tC'] as num?)?.toDouble();
                }
              }
            }
          }
        } catch (_) {}
      }
    } finally {
      if (shouldClose) {
        client.close();
      }
    }

    return device.copyWith(
      name: name,
      model: model,
      firmware: firmware,
      authEnabled: authEnabled,
      currentPowerW: currentPowerW,
      relayState: relayState,
      temperatureC: temperatureC,
    );
  }

  /// Discovers devices via mDNS and probes each discovered device via LAN HTTP.
  Future<List<DiscoveredShellyDevice>> discoverAndProbe({
    Duration discoveryTimeout = const Duration(seconds: 5),
    Duration probeTimeout = const Duration(seconds: 3),
  }) async {
    final discovered = await discover(timeout: discoveryTimeout);
    if (discovered.isEmpty) return const [];

    final client = http.Client();
    try {
      final probed = await Future.wait(
        discovered.map(
          (d) => probeDevice(d, timeout: probeTimeout, httpClient: client),
        ),
      );
      return probed;
    } finally {
      client.close();
    }
  }

  /// Detect the local IPv4 subnet prefix (e.g. '192.168.1.').
  Future<String?> detectLocalSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains('lo') ||
            iface.name.toLowerCase().contains('docker')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.contains('.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}.';
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Scans a /24 subnet by sending fast HTTP GET requests to each IP (1..254).
  /// Bypasses router multicast/mDNS blocks using standard TCP Unicast.
  Future<List<DiscoveredShellyDevice>> sweepSubnet({
    String? baseSubnet,
    Duration timeout = const Duration(milliseconds: 350),
    int batchSize = 30,
    void Function(double progress, int foundCount)? onProgress,
    http.Client? httpClient,
  }) async {
    String prefix = baseSubnet ?? await detectLocalSubnet() ?? '192.168.1.';
    if (!prefix.endsWith('.')) prefix = '$prefix.';

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    final found = <String, DiscoveredShellyDevice>{};

    try {
      final ips = List.generate(254, (i) => '$prefix${i + 1}');
      final total = ips.length;
      int completed = 0;

      for (int i = 0; i < total; i += batchSize) {
        final batch = ips.sublist(i, (i + batchSize > total) ? total : i + batchSize);
        final results = await Future.wait(
          batch.map((ip) async {
            try {
              final uri = Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo');
              final res = await client.get(uri).timeout(timeout);
              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                if (data is Map<String, dynamic>) {
                  final id = data['id']?.toString() ?? 'shelly-$ip';
                  final model = data['app']?.toString() ?? data['model']?.toString() ?? 'Shelly';
                  final name = data['name']?.toString();
                  final ver = data['ver']?.toString() ?? data['fw_id']?.toString();
                  final authEn = data['auth_en'] == true;
                  return DiscoveredShellyDevice(
                    id: id,
                    address: ip,
                    model: model,
                    name: name ?? id,
                    firmware: ver,
                    authEnabled: authEn,
                    generation: 3,
                  );
                }
              } else if (res.statusCode == 401) {
                return DiscoveredShellyDevice(
                  id: 'shelly-$ip',
                  address: ip,
                  model: 'Shelly (Protected)',
                  name: 'Shelly $ip',
                  authEnabled: true,
                  generation: 3,
                );
              }
            } catch (_) {
              try {
                final legUri = Uri.parse('http://$ip/shelly');
                final legRes = await client.get(legUri).timeout(const Duration(milliseconds: 200));
                if (legRes.statusCode == 200) {
                  final data = jsonDecode(legRes.body);
                  if (data is Map<String, dynamic>) {
                    final id = data['mac']?.toString() ?? 'shelly-$ip';
                    final model = data['type']?.toString() ?? 'Shelly';
                    return DiscoveredShellyDevice(
                      id: id,
                      address: ip,
                      model: model,
                      name: id,
                      generation: 1,
                    );
                  }
                }
              } catch (_) {}
            }
            return null;
          }),
        );

        for (final device in results) {
          if (device != null) {
            found[device.address] = device;
          }
        }

        completed += batch.length;
        if (onProgress != null) {
          onProgress(completed / total, found.length);
        }
      }
    } finally {
      if (shouldClose) {
        client.close();
      }
    }

    return found.values.toList(growable: false);
  }
}
