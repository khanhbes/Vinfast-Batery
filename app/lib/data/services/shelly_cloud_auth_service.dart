import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/shelly_connection.dart';

class ShellyCloudDevice {
  const ShellyCloudDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.cloudAuthKey,
    this.serverUri,
    this.isOnline = false,
  });

  final String id;
  final String name;
  final String type;
  final String cloudAuthKey;
  final String? serverUri;
  final bool isOnline;

  factory ShellyCloudDevice.fromJson(Map<String, dynamic> json, {String? defaultServer}) {
    return ShellyCloudDevice(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Shelly Device',
      type: json['type']?.toString() ?? '',
      cloudAuthKey: json['cloud_auth_key']?.toString() ?? json['auth_key']?.toString() ?? '',
      serverUri: json['server_uri']?.toString() ?? defaultServer,
      isOnline: json['online'] == true,
    );
  }
}

class ShellyCloudAuthService {
  ShellyCloudAuthService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Known default Shelly Cloud regions
  static const List<String> defaultCloudHosts = [
    'https://shelly-103-eu.shelly.cloud',
    'https://shelly-104-eu.shelly.cloud',
    'https://shelly-105-eu.shelly.cloud',
    'https://shelly-106-eu.shelly.cloud',
    'https://shelly-107-eu.shelly.cloud',
    'https://shelly-108-eu.shelly.cloud',
  ];

  /// Launch the Shelly Cloud login / token retrieval page in browser
  Future<bool> launchShellyCloudPortal() async {
    final uri = Uri.parse('https://control.shelly.cloud/#/user/profile');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// List devices from Shelly Cloud using an auth key and optional server host
  Future<List<ShellyCloudDevice>> listDevices({
    required String authKey,
    String? cloudHost,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final trimmedKey = authKey.trim();
    if (trimmedKey.isEmpty) return const [];

    final hostsToTry = <String>[];
    if (cloudHost != null && cloudHost.trim().isNotEmpty) {
      hostsToTry.add(_normalizeHost(cloudHost.trim()));
    } else {
      hostsToTry.addAll(defaultCloudHosts);
    }

    for (final host in hostsToTry) {
      // Try /interface/device/list first, then fallback to /device/all_status
      final endpoints = [
        '$host/interface/device/list?auth_key=$trimmedKey',
        '$host/device/all_status?auth_key=$trimmedKey',
      ];

      for (final endpointUrl in endpoints) {
        try {
          final uri = Uri.parse(endpointUrl);
          final response = await _client.post(
            uri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'auth_key': trimmedKey,
            },
          ).timeout(timeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map) {
              final container = (data['data'] is Map) ? data['data'] as Map : data;
              final devicesRaw = container['devices'] ?? container['devices_status'];

              if (devicesRaw is List) {
                return devicesRaw
                    .whereType<Map>()
                    .map((d) => ShellyCloudDevice.fromJson(Map<String, dynamic>.from(d), defaultServer: host))
                    .toList();
              } else if (devicesRaw is Map) {
                return devicesRaw.entries.map((entry) {
                  final key = entry.key.toString();
                  final val = entry.value;
                  if (val is Map) {
                    final map = Map<String, dynamic>.from(val);
                    map.putIfAbsent('id', () => key);
                    return ShellyCloudDevice.fromJson(map, defaultServer: host);
                  }
                  return ShellyCloudDevice(
                    id: key,
                    name: key,
                    type: '',
                    cloudAuthKey: trimmedKey,
                    serverUri: host,
                  );
                }).toList();
              }
            }
          }
        } on TimeoutException {
          continue;
        } on SocketException {
          continue;
        } on http.ClientException {
          continue;
        } on FormatException {
          continue;
        } catch (e) {
          if (e.runtimeType.toString().contains('TestFailure')) rethrow;
          continue;
        }
      }
    }

    return const [];
  }

  /// Match a discovered LAN device with devices in the user's Shelly Cloud account
  ShellyCloudDevice? matchDevice({
    required DiscoveredShellyDevice lanDevice,
    required List<ShellyCloudDevice> cloudDevices,
  }) {
    final lanIdNormalized = lanDevice.id.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');
    for (final cd in cloudDevices) {
      final cloudIdNormalized = cd.id.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');
      if (cloudIdNormalized == lanIdNormalized ||
          cloudIdNormalized.endsWith(lanIdNormalized) ||
          lanIdNormalized.endsWith(cloudIdNormalized)) {
        return cd;
      }
    }
    return null;
  }

  /// Automatically assemble a full ShellyConnectionProfile combining LAN discovery & Cloud device
  ShellyConnectionProfile assembleProfile({
    required DiscoveredShellyDevice lanDevice,
    ShellyCloudDevice? cloudDevice,
    String? cloudHost,
    String? cloudAuthKey,
    String? localPassword,
  }) {
    final host = cloudDevice?.serverUri ?? cloudHost ?? defaultCloudHosts.first;
    final key = cloudDevice?.cloudAuthKey.isNotEmpty == true
        ? cloudDevice!.cloudAuthKey
        : (cloudAuthKey ?? '');

    return ShellyConnectionProfile(
      cloudHost: host,
      cloudAuthKey: key,
      deviceId: cloudDevice?.id.isNotEmpty == true ? cloudDevice!.id : lanDevice.id,
      deviceName: lanDevice.name ?? cloudDevice?.name ?? 'Shelly Plug S Gen3',
      model: lanDevice.model.isNotEmpty ? lanDevice.model : 'S3PL-00112EU',
      firmware: lanDevice.firmware,
      lanAddress: lanDevice.address,
      localUsername: 'admin',
      localPassword: localPassword,
    );
  }

  String _normalizeHost(String host) {
    var h = host.trim();
    if (!h.startsWith('http://') && !h.startsWith('https://')) {
      h = 'https://$h';
    }
    return h.replaceAll(RegExp(r'/$'), '');
  }
}
