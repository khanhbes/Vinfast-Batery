import { 
  collection, 
  getDocs, 
  query, 
  orderBy, 
  limit, 
  Timestamp 
} from 'firebase/firestore';
import { db } from '@/firebase';

export interface VehicleData {
  vehicleId: string;
  vehicleName: string;
  ownerUid?: string;
  currentOdo: number;
  currentBattery: number;
  stateOfHealth: number;
  defaultEfficiency: number;
  totalCharges: number;
  totalTrips: number;
  lastBatteryPercent: number;
  avatarColor?: string;
  vinfastModelId?: string;
  vinfastModelName?: string;
  specVersion?: number;
  specLinkedAt?: Timestamp;
}

export interface AiVehicleInsight {
  vehicleId: string;
  ownerUid: string;
  hasTrained: boolean;
  trainedAt?: string;
  updatedAt?: string;
  profileVersion?: string;
  dataPoints: number;
  healthAdjustment: number;
  healthScore: number;
  healthStatus: string;
  estimatedLifeMonths?: number;
  confidence: number;
  peakChargingHour?: number;
  peakChargingDay?: string;
  chargeFrequencyPerWeek?: number;
  avgSessionDuration?: number;
  recommendations: string[];
  equivalentCycles?: number;
  remainingCycles?: number;
  avgDoD?: number;
}

export interface SOCPredictionInput {
  currentBattery: number;
  temperature: number;
  voltage: number;
  current: number;
  odometer: number;
  timeOfDay: number;
  dayOfWeek: number;
  avgSpeed: number;
  elevationGain: number;
  weatherCondition: string;
}

export interface SOCPredictionResult {
  predictedSOC: number;
  confidence: number;
  timeSeries: number[];
  batteryHealth: number;
  recommendations: string[];
  timestamp: string;
  modelVersion: string;
}

export interface ChargeLog {
  chargeId: string;
  vehicleId: string;
  startBatteryPercent: number;
  endBatteryPercent: number;
  startAt: Timestamp;
  endAt?: Timestamp;
  durationMinutes?: number;
  location?: string;
  chargerType?: string;
  temperature?: number;
  efficiency?: number;
}

export interface TripLog {
  tripId: string;
  vehicleId: string;
  startOdo: number;
  endOdo: number;
  distance: number;
  startBatteryPercent: number;
  endBatteryPercent: number;
  startAt: Timestamp;
  endAt?: Timestamp;
  durationMinutes?: number;
  avgSpeed?: number;
  efficiency?: number;
  location?: string;
}

export interface MaintenanceTask {
  taskId: string;
  vehicleId: string;
  taskType: string;
  description: string;
  dueOdo?: number;
  dueDate?: Timestamp;
  completedAt?: Timestamp;
  status: 'pending' | 'completed' | 'overdue';
  priority: 'low' | 'medium' | 'high';
  cost?: number;
}

class FirebaseService {
  // Lấy tất cả vehicles
  async getVehicles(): Promise<VehicleData[]> {
    try {
      const vehiclesRef = collection(db, 'Vehicles');
      const q = query(vehiclesRef, orderBy('updatedAt', 'desc'));
      const querySnapshot = await getDocs(q);
      
      return querySnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          vehicleId: doc.id,
          vehicleName: data['vehicleName'] || '',
          ownerUid: data['ownerUid'],
          currentOdo: data['currentOdo'] || 0,
          currentBattery: data['currentBattery'] || data['lastBatteryPercent'] || 100,
          stateOfHealth: (data['stateOfHealth'] || 100.0) as number,
          defaultEfficiency: (data['defaultEfficiency'] || 1.2) as number,
          totalCharges: data['totalCharges'] || 0,
          totalTrips: data['totalTrips'] || 0,
          lastBatteryPercent: data['lastBatteryPercent'] || 100,
          avatarColor: data['avatarColor'],
          vinfastModelId: data['vinfastModelId'],
          vinfastModelName: data['vinfastModelName'],
          specVersion: data['specVersion'],
          specLinkedAt: data['specLinkedAt'],
        } as VehicleData;
      });
    } catch (error) {
      console.error('Error fetching vehicles:', error);
      return [];
    }
  }

  // Lấy AI insights cho tất cả vehicles
  async getAiInsights(): Promise<AiVehicleInsight[]> {
    try {
      const insightsRef = collection(db, 'AiVehicleInsights');
      const q = query(insightsRef, orderBy('updatedAt', 'desc'), limit(100));
      const querySnapshot = await getDocs(q);
      
      return querySnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          vehicleId: data['vehicleId'] || '',
          ownerUid: data['ownerUid'] || '',
          hasTrained: data['hasTrained'] || false,
          trainedAt: data['trainedAt']?.toString(),
          profileVersion: data['profileVersion']?.toString(),
          dataPoints: data['dataPoints'] || 0,
          healthAdjustment: (data['healthAdjustment'] || 0) as number,
          healthScore: (data['healthScore'] || 100) as number,
          healthStatus: data['healthStatus'] || 'Chưa có dữ liệu',
          estimatedLifeMonths: data['estimatedLifeMonths'] as number,
          confidence: (data['confidence'] || 0) as number,
          peakChargingHour: data['peakChargingHour'] as number,
          peakChargingDay: data['peakChargingDay']?.toString(),
          chargeFrequencyPerWeek: data['chargeFrequencyPerWeek'] as number,
          avgSessionDuration: data['avgSessionDuration'] as number,
          recommendations: (data['recommendations'] || []) as string[],
          equivalentCycles: data['equivalentCycles'] as number,
          remainingCycles: data['remainingCycles'] as number,
          avgDoD: data['avgDoD'] as number,
          avgChargeRate: data['avgChargeRate'] as number,
          patterns: data['patterns'] || [],
          lastInferenceAt: data['lastInferenceAt']?.toString(),
          lastInferenceStatus: data['lastInferenceStatus'] || 'unknown',
          lastInferenceError: data['lastInferenceError']?.toString(),
          updatedAt: data['updatedAt']?.toString(),
          schemaVersion: data['schemaVersion'] || 'insight-v1',
        } as AiVehicleInsight;
      });
    } catch (error) {
      console.error('Error fetching AI insights:', error);
      return [];
    }
  }

  // Lấy charge logs gần đây
  async getRecentChargeLogs(limitCount: number = 50): Promise<ChargeLog[]> {
    try {
      const chargeLogsRef = collection(db, 'ChargeLogs');
      const q = query(chargeLogsRef, orderBy('startAt', 'desc'), limit(limitCount));
      const querySnapshot = await getDocs(q);
      
      return querySnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          chargeId: doc.id,
          vehicleId: data['vehicleId'] || '',
          startBatteryPercent: data['startBatteryPercent'] || 0,
          endBatteryPercent: data['endBatteryPercent'] || 0,
          startAt: data['startAt'] as Timestamp,
          endAt: data['endAt'] as Timestamp,
          durationMinutes: data['durationMinutes'] as number,
          location: data['location']?.toString(),
          chargerType: data['chargerType']?.toString(),
          temperature: data['temperature'] as number,
          efficiency: data['efficiency'] as number,
        } as ChargeLog;
      });
    } catch (error) {
      console.error('Error fetching charge logs:', error);
      return [];
    }
  }

  // Lấy trip logs gần đây
  async getRecentTripLogs(limitCount: number = 50): Promise<TripLog[]> {
    try {
      const tripLogsRef = collection(db, 'TripLogs');
      const q = query(tripLogsRef, orderBy('startAt', 'desc'), limit(limitCount));
      const querySnapshot = await getDocs(q);
      
      return querySnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          tripId: doc.id,
          vehicleId: data['vehicleId'] || '',
          startOdo: data['startOdo'] || 0,
          endOdo: data['endOdo'] || 0,
          distance: data['distance'] || 0,
          startBatteryPercent: data['startBatteryPercent'] || 0,
          endBatteryPercent: data['endBatteryPercent'] || 0,
          startAt: data['startAt'] as Timestamp,
          endAt: data['endAt'] as Timestamp,
          durationMinutes: data['durationMinutes'] as number,
          avgSpeed: data['avgSpeed'] as number,
          efficiency: data['efficiency'] as number,
          location: data['location']?.toString(),
        } as TripLog;
      });
    } catch (error) {
      console.error('Error fetching trip logs:', error);
      return [];
    }
  }

  // Lấy maintenance tasks
  async getMaintenanceTasks(): Promise<MaintenanceTask[]> {
    try {
      const maintenanceRef = collection(db, 'MaintenanceTasks');
      const q = query(maintenanceRef, orderBy('dueDate', 'asc'));
      const querySnapshot = await getDocs(q);
      
      return querySnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          taskId: doc.id,
          vehicleId: data['vehicleId'] || '',
          taskType: data['taskType'] || '',
          description: data['description'] || '',
          dueOdo: data['dueOdo'] as number,
          dueDate: data['dueDate'] as Timestamp,
          completedAt: data['completedAt'] as Timestamp,
          status: data['status'] || 'pending',
          priority: data['priority'] || 'medium',
          cost: data['cost'] as number,
        } as MaintenanceTask;
      });
    } catch (error) {
      console.error('Error fetching maintenance tasks:', error);
      return [];
    }
  }

  // Lấy thống kê tổng quan
  async getDashboardStats() {
    try {
      const vehicles = await this.getVehicles();
      const insights = await this.getAiInsights();
      const maintenanceTasks = await this.getMaintenanceTasks();

      const activeVehicles = vehicles.filter(v => v.currentBattery > 0).length;
      const avgSoH = vehicles.length > 0 
        ? vehicles.reduce((sum, v) => sum + v.stateOfHealth, 0) / vehicles.length 
        : 0;
      const lowBatteryVehicles = vehicles.filter(v => v.currentBattery < 20).length;
      const overdueMaintenance = maintenanceTasks.filter(t => t.status === 'overdue').length;

      return {
        totalUsers: new Set(vehicles.map(v => v.ownerUid).filter(Boolean)).size,
        activeVehicles,
        avgSoH: avgSoH.toFixed(1),
        alertsToday: lowBatteryVehicles + overdueMaintenance,
        totalVehicles: vehicles.length,
        totalCharges: vehicles.reduce((sum, v) => sum + v.totalCharges, 0),
        totalTrips: vehicles.reduce((sum, v) => sum + v.totalTrips, 0),
        trainedModels: insights.filter(i => i.hasTrained).length,
      };
    } catch (error) {
      console.error('Error fetching dashboard stats:', error);
      return {
        totalUsers: 0,
        activeVehicles: 0,
        avgSoH: '0',
        alertsToday: 0,
        totalVehicles: 0,
        totalCharges: 0,
        totalTrips: 0,
        trainedModels: 0,
      };
    }
  }

  // Dự đoán SOC bằng cách gọi API từ app
  async predictSOC(input: SOCPredictionInput): Promise<SOCPredictionResult> {
    try {
      const response = await fetch('http://localhost:5000/api/soc/predict', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(input),
      });

      if (!response.ok) {
        throw new Error(`SOC prediction failed: ${response.statusText}`);
      }

      const result = await response.json();
      return result.data as SOCPredictionResult;
    } catch (error) {
      console.error('Error predicting SOC:', error);
      throw error;
    }
  }

  // Lấy trạng thái model SOC
  async getSOCModelStatus() {
    try {
      const response = await fetch('http://localhost:5000/api/soc/status');
      
      if (!response.ok) {
        throw new Error(`Failed to get SOC model status: ${response.statusText}`);
      }

      const result = await response.json();
      return result.data;
    } catch (error) {
      console.error('Error getting SOC model status:', error);
      throw error;
    }
  }

  // Lấy lịch sử dự đoán SOC
  async getSOCPredictionHistory(vehicleId: string, limit: number = 10): Promise<SOCPredictionResult[]> {
    try {
      const response = await fetch(`http://localhost:5000/api/soc/history?vehicleId=${vehicleId}&limit=${limit}`);
      
      if (!response.ok) {
        throw new Error(`Failed to get SOC prediction history: ${response.statusText}`);
      }

      const result = await response.json();
      return result.data.predictions as SOCPredictionResult[];
    } catch (error) {
      console.error('Error getting SOC prediction history:', error);
      throw error;
    }
  }

  // Lấy tất cả predictions từ Firestore
  async getSOCPredictions() {
    try {
      const predictionsRef = collection(db, 'soc_predictions');
      const snapshot = await getDocs(predictionsRef);
      
      return snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
    } catch (error) {
      console.error('Error fetching SOC predictions:', error);
      return [];
    }
  }
}

export const firebaseService = new FirebaseService();
