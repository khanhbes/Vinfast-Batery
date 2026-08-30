import '../models/personal_charging_profile.dart';
import 'server_smart_charger_service.dart';

class PersonalAiService {
  PersonalAiService({ServerSmartChargerService? server})
    : _server = server ?? ServerSmartChargerService();

  final ServerSmartChargerService _server;

  Future<PersonalChargingProfile> profile(String vehicleId) =>
      _server.getPersonalProfile(vehicleId);

  Future<PersonalChargingProfile> setConsent(String vehicleId, bool enabled) =>
      _server.setPersonalAiConsent(vehicleId, enabled);

  Future<void> delete(String vehicleId) =>
      _server.deletePersonalProfile(vehicleId);
}
