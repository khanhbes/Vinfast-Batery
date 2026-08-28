import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../models/shelly_connection.dart';

class ShellyDiscoveryService {
  const ShellyDiscoveryService();

  Future<List<DiscoveredShellyDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MDnsClient();
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
    } on TimeoutException {
      // A quiet LAN is a valid empty discovery result.
    } finally {
      client.stop();
    }
    return devices.values.toList(growable: false);
  }
}
