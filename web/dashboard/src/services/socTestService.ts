import { SOCPredictionInput, SOCPredictionResult } from './firebaseService';

/// ========================================================================
/// SOC TEST SERVICE - Validation and testing for SOC integration
/// ========================================================================

export class SOCTestService {
  // Test data for SOC prediction
  static getTestData(): SOCPredictionInput {
    return {
      currentBattery: 75.0,
      temperature: 25.5,
      voltage: 48.2,
      current: 15.3,
      odometer: 12500.0,
      timeOfDay: 14,
      dayOfWeek: 2,
      avgSpeed: 45.0,
      elevationGain: 120.0,
      weatherCondition: 'sunny'
    };
  }

  // Test SOC prediction API
  static async testSOCPrediction(): Promise<boolean> {
    try {
      console.log('🧪 Testing SOC Prediction API...');
      
      const testData = this.getTestData();
      console.log('📊 Test data:', testData);

      const response = await fetch('http://localhost:8080/api/soc/predict', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(testData),
      });

      if (!response.ok) {
        console.error('❌ SOC Prediction API test failed:', response.statusText);
        return false;
      }

      const result = await response.json();
      console.log('✅ SOC Prediction API test successful:', result);

      // Validate response structure
      if (!result.success || !result.data) {
        console.error('❌ Invalid response structure:', result);
        return false;
      }

      const prediction: SOCPredictionResult = result.data;
      
      // Validate prediction data
      if (typeof prediction.predictedSOC !== 'number' || 
          typeof prediction.confidence !== 'number' ||
          !Array.isArray(prediction.timeSeries)) {
        console.error('❌ Invalid prediction data structure:', prediction);
        return false;
      }

      console.log('📈 Prediction results:');
      console.log(`  - Predicted SOC: ${prediction.predictedSOC.toFixed(1)}%`);
      console.log(`  - Confidence: ${prediction.confidence.toFixed(1)}%`);
      console.log(`  - Battery Health: ${prediction.batteryHealth.toFixed(1)}%`);
      console.log(`  - Time Series Length: ${prediction.timeSeries.length}`);
      console.log(`  - Recommendations: ${prediction.recommendations.length}`);

      return true;
    } catch (error) {
      console.error('❌ SOC Prediction API test error:', error);
      return false;
    }
  }

  // Test SOC model status API
  static async testModelStatus(): Promise<boolean> {
    try {
      console.log('🧪 Testing SOC Model Status API...');
      
      const response = await fetch('http://localhost:8080/api/soc/status');

      if (!response.ok) {
        console.error('❌ Model Status API test failed:', response.statusText);
        return false;
      }

      const result = await response.json();
      console.log('✅ Model Status API test successful:', result);

      if (!result.success || !result.data) {
        console.error('❌ Invalid status response structure:', result);
        return false;
      }

      const status = result.data;
      console.log('📊 Model status:');
      console.log(`  - Is Loaded: ${status.isLoaded}`);
      console.log(`  - Model Version: ${status.modelVersion}`);
      console.log(`  - Model Path: ${status.modelPath}`);

      return true;
    } catch (error) {
      console.error('❌ Model Status API test error:', error);
      return false;
    }
  }

  // Test SOC history API
  static async testPredictionHistory(): Promise<boolean> {
    try {
      console.log('🧪 Testing SOC Prediction History API...');
      
      const testVehicleId = 'test-vehicle-001';
      const response = await fetch(`http://localhost:8080/api/soc/history?vehicleId=${testVehicleId}&limit=5`);

      if (!response.ok) {
        console.error('❌ History API test failed:', response.statusText);
        return false;
      }

      const result = await response.json();
      console.log('✅ History API test successful:', result);

      if (!result.success || !result.data) {
        console.error('❌ Invalid history response structure:', result);
        return false;
      }

      const history = result.data;
      console.log('📊 Prediction history:');
      console.log(`  - Vehicle ID: ${history.vehicleId}`);
      console.log(`  - Count: ${history.count}`);
      console.log(`  - Predictions: ${history.predictions.length}`);

      return true;
    } catch (error) {
      console.error('❌ History API test error:', error);
      return false;
    }
  }

  // Run all tests
  static async runAllTests(): Promise<void> {
    console.log('🚀 Starting SOC Integration Tests...\n');

    const results = {
      modelStatus: await this.testModelStatus(),
      prediction: await this.testSOCPrediction(),
      history: await this.testPredictionHistory(),
    };

    console.log('\n📋 Test Results Summary:');
    console.log(`  - Model Status: ${results.modelStatus ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`  - Prediction: ${results.prediction ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`  - History: ${results.history ? '✅ PASS' : '❌ FAIL'}`);

    const allPassed = Object.values(results).every(result => result);
    
    if (allPassed) {
      console.log('\n🎉 All tests passed! SOC integration is working correctly.');
    } else {
      console.log('\n⚠️ Some tests failed. Please check the API server and model integration.');
    }

    console.log('\n💡 Next steps:');
    console.log('  1. Make sure the Flutter app is running with SOC API server');
    console.log('  2. Check that ev_soc_pipeline.pkl is properly loaded');
    console.log('  3. Verify Firebase connectivity for data persistence');
    console.log('  4. Test the web dashboard AI Center page');
  }
}

// Export for easy testing in browser console
declare global {
  interface Window {
    socTestService: typeof SOCTestService;
  }
}

// Make available in browser for manual testing
if (typeof window !== 'undefined') {
  window.socTestService = SOCTestService;
}
