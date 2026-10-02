import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/widgets/battery_bot_mascot.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';

void main() {
  group('AssistantContextCoordinator Tests', () {
    late AssistantContextCoordinator coordinator;

    setUp(() {
      coordinator = AssistantContextCoordinator(
        cooldownDuration: const Duration(minutes: 15),
        bubbleDisplayDuration: const Duration(seconds: 2),
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Initial state has no visible bubble', () {
      expect(coordinator.isBubbleVisible, isFalse);
      expect(coordinator.bubbleText, isNull);
      expect(coordinator.bubbleMood, equals(BatteryBotMood.idle));
      expect(coordinator.quickActionChips, isEmpty);
    });

    test('showBubble updates state and can be dismissed', () {
      coordinator.showBubble(
        'Xin chào!',
        mood: BatteryBotMood.greeting,
        chips: ['Câu hỏi 1'],
      );

      expect(coordinator.isBubbleVisible, isTrue);
      expect(coordinator.bubbleText, equals('Xin chào!'));
      expect(coordinator.bubbleMood, equals(BatteryBotMood.greeting));
      expect(coordinator.quickActionChips, equals(['Câu hỏi 1']));

      coordinator.dismissBubble();
      expect(coordinator.isBubbleVisible, isFalse);
    });

    test('Low battery trigger activates when SoC < 20%', () {
      final lowBatteryVehicle = VehicleModel(
        vehicleId: 'test_veh_1',
        vehicleName: 'VinFast Feliz S',
        currentOdo: 1000,
        currentBattery: 15,
      );

      final triggered = coordinator.evaluateContext(
        vehicle: lowBatteryVehicle,
        currentTab: 0,
        now: DateTime(2026, 9, 29, 14, 0), // Không phải buổi sáng
      );

      expect(triggered, isTrue);
      expect(coordinator.isBubbleVisible, isTrue);
      expect(coordinator.bubbleText, contains('15%'));
      expect(coordinator.bubbleMood, equals(BatteryBotMood.thinking));

      // Không trigger lại ngay lập tức vì cooldown
      final retriggered = coordinator.evaluateContext(
        vehicle: lowBatteryVehicle,
        currentTab: 0,
        now: DateTime(2026, 9, 29, 14, 5),
      );
      expect(retriggered, isFalse);
    });

    test('Morning greeting triggers between 6:00 and 8:59', () {
      final normalVehicle = VehicleModel(
        vehicleId: 'test_veh_2',
        vehicleName: 'VinFast Evo 200',
        currentOdo: 2500,
        currentBattery: 85,
      );

      final morningTime = DateTime(2026, 9, 29, 7, 30);
      final triggered = coordinator.evaluateContext(
        vehicle: normalVehicle,
        currentTab: 0,
        now: morningTime,
      );

      expect(triggered, isTrue);
      expect(coordinator.isBubbleVisible, isTrue);
      expect(coordinator.bubbleText, contains('Chào buổi sáng!'));
      expect(coordinator.bubbleMood, equals(BatteryBotMood.greeting));
    });

    test('Charging tab hint triggers when currentTab == 1', () {
      final normalVehicle = VehicleModel(
        vehicleId: 'test_veh_3',
        vehicleName: 'VinFast Klara S',
        currentOdo: 5000,
        currentBattery: 60,
      );

      final afternoonTime = DateTime(2026, 9, 29, 15, 0);
      final triggered = coordinator.evaluateContext(
        vehicle: normalVehicle,
        currentTab: 1, // Sạc pin tab
        now: afternoonTime,
      );

      expect(triggered, isTrue);
      expect(coordinator.isBubbleVisible, isTrue);
      expect(coordinator.bubbleText, contains('80-90%'));
      expect(coordinator.bubbleMood, equals(BatteryBotMood.charging));
    });
  });
}
