"""
VinFast Battery — AI Battery Degradation Prediction API
Flask Backend Server (Phase 2)

Endpoints:
  POST /api/predict-degradation   → Dự đoán chai pin
  POST /api/analyze-patterns      → Phân tích thói quen sạc
  GET  /api/health                → Health check
"""

import os
import math
import numpy as np
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)
app.secret_key = os.urandom(24)


# =============================================================================
# AI MODEL — Battery Degradation Prediction
# =============================================================================

class BatteryDegradationModel:
    """
    Mô hình dự đoán chai pin dựa trên phân tích chu kỳ sạc.

    Phase 2: Rule-based + Statistical analysis
    Phase 3: Sẽ chuyển sang ML (Random Forest / LSTM)

    Các yếu tố ảnh hưởng tuổi thọ pin lithium-ion:
    1. Số chu kỳ sạc (cycle count)
    2. Độ sâu xả (Depth of Discharge - DoD)
    3. Tốc độ sạc (charge rate = %/hour)
    4. Nhiệt độ sạc (chưa có sensor → ước lượng từ thời gian)
    5. Thời gian pin ở mức cao (>80%) hoặc thấp (<20%)
    """

    # Thông số pin lithium-ion VinFast (ước lượng)
    MAX_CYCLES = 800           # Số chu kỳ sạc tối đa lý thuyết (0→100%)
    NOMINAL_CAPACITY_KWH = 1.5  # Dung lượng danh định (kWh)
    CRITICAL_HEALTH = 60       # % sức khỏe cần thay pin

    def predict_degradation(self, charge_logs: list) -> dict:
        """
        Dự đoán mức độ chai pin từ lịch sử sạc.

        Input: charge_logs — danh sách dict với keys:
            startBatteryPercent, endBatteryPercent,
            startTime (ISO string), endTime (ISO string),
            odoAtCharge

        Output: dict với các chỉ số sức khỏe pin
        """
        if not charge_logs or len(charge_logs) < 3:
            return {
                'healthScore': 100.0,
                'healthStatus': 'Chưa đủ dữ liệu',
                'healthStatusCode': 'insufficient_data',
                'equivalentCycles': 0,
                'remainingCycles': self.MAX_CYCLES,
                'estimatedLifeMonths': None,
                'avgChargeRate': 0,
                'avgDoD': 0,
                'degradationFactors': [],
                'recommendations': ['Cần ít nhất 3 lần sạc để phân tích'],
                'confidence': 0.0,
            }

        # ── 1. Tính toán các chỉ số cơ bản ──
        equivalent_cycles = self._calculate_equivalent_cycles(charge_logs)
        avg_dod = self._calculate_avg_dod(charge_logs)
        avg_charge_rate = self._calculate_avg_charge_rate(charge_logs)
        charge_rate_trend = self._calculate_charge_rate_trend(charge_logs)
        total_odo = self._calculate_total_odo(charge_logs)

        # ── 2. Tính điểm sức khỏe (0-100) ──
        # Mô hình: SoH = 100 - (cycle_aging + stress_aging)
        cycle_aging = (equivalent_cycles / self.MAX_CYCLES) * 100

        # Stress factors
        dod_stress = self._dod_stress_factor(avg_dod)
        rate_stress = self._rate_stress_factor(avg_charge_rate)
        calendar_stress = self._calendar_stress(charge_logs)

        total_aging = cycle_aging * (1 + dod_stress + rate_stress) + calendar_stress
        health_score = max(0, min(100, 100 - total_aging))

        # ── 3. Dự đoán tuổi thọ còn lại ──
        remaining_cycles = max(0, self.MAX_CYCLES - equivalent_cycles)
        avg_cycles_per_month = self._avg_cycles_per_month(charge_logs)
        estimated_life_months = (
            round(remaining_cycles / avg_cycles_per_month, 1)
            if avg_cycles_per_month > 0
            else None
        )

        # ── 4. Phân tích yếu tố degradation ──
        factors = self._analyze_degradation_factors(
            avg_dod, avg_charge_rate, charge_rate_trend, equivalent_cycles
        )

        # ── 5. Đề xuất cải thiện ──
        recommendations = self._generate_recommendations(
            health_score, avg_dod, avg_charge_rate, charge_rate_trend
        )

        # ── 6. Độ tin cậy (dựa trên số lượng dữ liệu) ──
        confidence = min(1.0, len(charge_logs) / 50) * 100

        # Health status text
        if health_score >= 80:
            status = 'Tốt'
            status_code = 'good'
        elif health_score >= 60:
            status = 'Khá'
            status_code = 'fair'
        elif health_score >= 40:
            status = 'Trung bình'
            status_code = 'average'
        else:
            status = 'Cần thay pin'
            status_code = 'poor'

        return {
            'healthScore': round(health_score, 1),
            'healthStatus': status,
            'healthStatusCode': status_code,
            'equivalentCycles': round(equivalent_cycles, 1),
            'remainingCycles': round(remaining_cycles, 1),
            'estimatedLifeMonths': estimated_life_months,
            'avgChargeRate': round(avg_charge_rate, 2),
            'avgDoD': round(avg_dod, 1),
            'chargeRateTrend': round(charge_rate_trend, 3),
            'totalOdometer': total_odo,
            'degradationFactors': factors,
            'recommendations': recommendations,
            'confidence': round(confidence, 1),
            'modelVersion': '2.0-statistical',
        }

    # ── Tính toán chu kỳ tương đương ──
    def _calculate_equivalent_cycles(self, logs: list) -> float:
        """
        1 equivalent cycle = 1 lần sạc 0% → 100%.
        Ví dụ: sạc 20% → 80% = 0.6 equivalent cycle.
        """
        total = 0
        for log in logs:
            gain = log['endBatteryPercent'] - log['startBatteryPercent']
            total += gain / 100.0
        return total

    # ── Tính DoD trung bình ──
    def _calculate_avg_dod(self, logs: list) -> float:
        """Depth of Discharge trung bình (% pin trước khi sạc)"""
        if not logs:
            return 0
        total_dod = sum(100 - log['startBatteryPercent'] for log in logs)
        return total_dod / len(logs)

    # ── Tính tốc độ sạc trung bình ──
    def _calculate_avg_charge_rate(self, logs: list) -> float:
        """Tốc độ sạc trung bình (%/giờ)"""
        rates = []
        for log in logs:
            try:
                start = datetime.fromisoformat(log['startTime'])
                end = datetime.fromisoformat(log['endTime'])
                hours = (end - start).total_seconds() / 3600
                if hours > 0:
                    gain = log['endBatteryPercent'] - log['startBatteryPercent']
                    rates.append(gain / hours)
            except (ValueError, KeyError):
                continue
        return sum(rates) / len(rates) if rates else 0

    # ── Xu hướng tốc độ sạc (degradation signal) ──
    def _calculate_charge_rate_trend(self, logs: list) -> float:
        """
        Slope của tốc độ sạc theo thời gian.
        Giá trị âm = pin đang sạc chậm dần → degradation.
        """
        rates = []
        for log in sorted(logs, key=lambda x: x['startTime']):
            try:
                start = datetime.fromisoformat(log['startTime'])
                end = datetime.fromisoformat(log['endTime'])
                hours = (end - start).total_seconds() / 3600
                if hours > 0:
                    gain = log['endBatteryPercent'] - log['startBatteryPercent']
                    rates.append(gain / hours)
            except (ValueError, KeyError):
                continue

        if len(rates) < 3:
            return 0.0

        # Simple linear regression
        n = len(rates)
        x = list(range(n))
        x_mean = sum(x) / n
        y_mean = sum(rates) / n

        numerator = sum((x[i] - x_mean) * (rates[i] - y_mean) for i in range(n))
        denominator = sum((x[i] - x_mean) ** 2 for i in range(n))

        return numerator / denominator if denominator != 0 else 0.0

    # ── Tổng ODO ──
    def _calculate_total_odo(self, logs: list) -> int:
        if not logs:
            return 0
        odos = [log.get('odoAtCharge', 0) for log in logs]
        return max(odos) if odos else 0

    # ── Stress factors ──
    def _dod_stress_factor(self, avg_dod: float) -> float:
        """
        DoD cao → pin hao mòn nhanh hơn.
        DoD 80% = stress x1.5; DoD 50% = stress x1.0
        """
        if avg_dod <= 50:
            return 0.0
        return (avg_dod - 50) / 100.0

    def _rate_stress_factor(self, avg_rate: float) -> float:
        """Tốc độ sạc nhanh → stress pin cao hơn"""
        if avg_rate <= 20:
            return 0.0
        return (avg_rate - 20) / 100.0

    def _calendar_stress(self, logs: list) -> float:
        """Tuổi pin tính từ lần sạc đầu tiên"""
        try:
            times = [datetime.fromisoformat(l['startTime']) for l in logs]
            if not times:
                return 0
            oldest = min(times)
            age_days = (datetime.now() - oldest).days
            # ~2% degradation per year from calendar aging
            return (age_days / 365) * 2.0
        except (ValueError, KeyError):
            return 0

    # ── Chu kỳ sạc/tháng ──
    def _avg_cycles_per_month(self, logs: list) -> float:
        try:
            times = [datetime.fromisoformat(l['startTime']) for l in logs]
            if len(times) < 2:
                return 0
            oldest = min(times)
            newest = max(times)
            months = max(1, (newest - oldest).days / 30)
            equivalent = self._calculate_equivalent_cycles(logs)
            return equivalent / months
        except (ValueError, KeyError):
            return 0

    # ── Phân tích yếu tố ──
    def _analyze_degradation_factors(
        self, avg_dod, avg_rate, rate_trend, eq_cycles
    ) -> list:
        factors = []

        if eq_cycles > self.MAX_CYCLES * 0.7:
            factors.append({
                'factor': 'Số chu kỳ sạc cao',
                'severity': 'high',
                'detail': f'{eq_cycles:.0f}/{self.MAX_CYCLES} chu kỳ tương đương',
            })

        if avg_dod > 80:
            factors.append({
                'factor': 'Xả pin quá sâu',
                'severity': 'high',
                'detail': f'DoD trung bình {avg_dod:.0f}% (khuyến nghị < 80%)',
            })
        elif avg_dod > 60:
            factors.append({
                'factor': 'Mức xả pin trung bình',
                'severity': 'medium',
                'detail': f'DoD trung bình {avg_dod:.0f}%',
            })

        if rate_trend < -0.1:
            factors.append({
                'factor': 'Tốc độ sạc giảm dần',
                'severity': 'medium',
                'detail': f'Giảm {abs(rate_trend):.2f} %/h mỗi chu kỳ',
            })

        if avg_rate > 30:
            factors.append({
                'factor': 'Sạc quá nhanh',
                'severity': 'medium',
                'detail': f'Tốc độ TB {avg_rate:.1f} %/h (khuyến nghị < 30%/h)',
            })

        if not factors:
            factors.append({
                'factor': 'Không phát hiện vấn đề',
                'severity': 'low',
                'detail': 'Pin đang hoạt động bình thường',
            })

        return factors

    # ── Đề xuất cải thiện ──
    def _generate_recommendations(
        self, health_score, avg_dod, avg_rate, rate_trend
    ) -> list:
        recs = []

        if avg_dod > 80:
            recs.append(
                '🔋 Hãy sạc pin sớm hơn — tránh để pin dưới 20% trước khi sạc'
            )

        if avg_rate > 30:
            recs.append(
                '⚡ Giảm tốc độ sạc — sạc chậm giúp pin bền hơn'
            )

        if rate_trend < -0.1:
            recs.append(
                '📉 Tốc độ sạc đang giảm — theo dõi thêm và cân nhắc kiểm tra pin'
            )

        if health_score < 60:
            recs.append(
                '🔧 Sức khỏe pin dưới 60% — nên đến trung tâm VinFast kiểm tra'
            )

        if not recs:
            recs.append(
                '✅ Pin đang hoạt động tốt — tiếp tục duy trì thói quen sạc hiện tại'
            )

        return recs


class ChargingPatternAnalyzer:
    """Phân tích thói quen sạc của người dùng"""

    def analyze(self, charge_logs: list) -> dict:
        if not charge_logs or len(charge_logs) < 3:
            return {
                'peakChargingHour': None,
                'peakChargingDay': None,
                'avgCycleDays': None,
                'chargeFrequencyPerWeek': None,
                'avgSessionDuration': None,
                'preferredChargeRange': None,
                'patterns': [],
            }

        # Giờ sạc phổ biến
        hour_counts = [0] * 24
        for log in charge_logs:
            try:
                t = datetime.fromisoformat(log['startTime'])
                hour_counts[t.hour] += 1
            except (ValueError, KeyError):
                pass
        peak_hour = hour_counts.index(max(hour_counts))

        # Ngày sạc phổ biến
        day_counts = [0] * 7
        day_names = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật']
        for log in charge_logs:
            try:
                t = datetime.fromisoformat(log['startTime'])
                day_counts[t.weekday()] += 1
            except (ValueError, KeyError):
                pass
        peak_day_idx = day_counts.index(max(day_counts))

        # Chu kỳ trung bình giữa các lần sạc
        try:
            times = sorted([
                datetime.fromisoformat(l['startTime'])
                for l in charge_logs
            ])
            if len(times) > 1:
                gaps = [(times[i] - times[i-1]).total_seconds() / 86400
                        for i in range(1, len(times))]
                avg_cycle_days = sum(gaps) / len(gaps)
            else:
                avg_cycle_days = None
        except (ValueError, KeyError):
            avg_cycle_days = None

        # Tần suất sạc/tuần
        freq = 7 / avg_cycle_days if avg_cycle_days and avg_cycle_days > 0 else None

        # Thời gian sạc trung bình
        durations = []
        for log in charge_logs:
            try:
                s = datetime.fromisoformat(log['startTime'])
                e = datetime.fromisoformat(log['endTime'])
                durations.append((e - s).total_seconds() / 3600)
            except (ValueError, KeyError):
                pass
        avg_duration = sum(durations) / len(durations) if durations else None

        # Khoảng sạc ưa thích
        starts = [l['startBatteryPercent'] for l in charge_logs]
        ends = [l['endBatteryPercent'] for l in charge_logs]
        preferred_range = {
            'avgStart': round(sum(starts) / len(starts)),
            'avgEnd': round(sum(ends) / len(ends)),
        }

        # Nhận diện patterns
        patterns = []
        if peak_hour >= 22 or peak_hour <= 5:
            patterns.append('🌙 Thường sạc vào ban đêm')
        elif peak_hour >= 6 and peak_hour <= 9:
            patterns.append('🌅 Thường sạc vào buổi sáng')
        elif peak_hour >= 17 and peak_hour <= 21:
            patterns.append('🌆 Thường sạc vào buổi tối')

        if preferred_range['avgStart'] < 20:
            patterns.append('⚠️ Thường xả pin rất sâu trước khi sạc')
        elif preferred_range['avgStart'] > 40:
            patterns.append('👍 Sạc pin khi còn nhiều — tốt cho tuổi thọ')

        if preferred_range['avgEnd'] >= 95:
            patterns.append('🔌 Thường sạc đầy 100%')

        return {
            'peakChargingHour': f'{peak_hour:02d}:00',
            'peakChargingDay': day_names[peak_day_idx],
            'avgCycleDays': round(avg_cycle_days, 1) if avg_cycle_days else None,
            'chargeFrequencyPerWeek': round(freq, 1) if freq else None,
            'avgSessionDuration': round(avg_duration, 1) if avg_duration else None,
            'preferredChargeRange': preferred_range,
            'patterns': patterns,
        }


# =============================================================================
# MODEL INSTANCES
# =============================================================================

degradation_model = BatteryDegradationModel()
pattern_analyzer = ChargingPatternAnalyzer()


# =============================================================================
# API ENDPOINTS
# =============================================================================

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'VinFast Battery AI API',
        'version': '2.0',
        'models': ['battery-degradation-v2', 'charging-pattern-v1'],
    })


@app.route('/api/predict-degradation', methods=['POST'])
def predict_degradation():
    """
    Dự đoán chai pin từ lịch sử sạc.

    Request body:
    {
        "vehicleId": "VF-OPES-001",
        "chargeLogs": [
            {
                "startBatteryPercent": 15,
                "endBatteryPercent": 100,
                "startTime": "2026-03-01T08:00:00",
                "endTime": "2026-03-01T11:30:00",
                "odoAtCharge": 1250
            },
            ...
        ]
    }

    Response:
    {
        "success": true,
        "data": {
            "healthScore": 87.3,
            "healthStatus": "Tốt",
            "equivalentCycles": 23.5,
            "remainingCycles": 776.5,
            "estimatedLifeMonths": 48.2,
            ...
        }
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'Dữ liệu không hợp lệ'}), 400

    charge_logs = data.get('chargeLogs', [])
    vehicle_id = data.get('vehicleId', '')

    if not charge_logs:
        return jsonify({
            'success': False,
            'error': 'Cần cung cấp danh sách chargeLogs',
        }), 400

    try:
        prediction = degradation_model.predict_degradation(charge_logs)
        prediction['vehicleId'] = vehicle_id
        prediction['analyzedAt'] = datetime.now().isoformat()

        return jsonify({'success': True, 'data': prediction})

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Lỗi phân tích: {str(e)}',
        }), 500


@app.route('/api/analyze-patterns', methods=['POST'])
def analyze_patterns():
    """
    Phân tích thói quen sạc.

    Request body:
    {
        "vehicleId": "VF-OPES-001",
        "chargeLogs": [ ... ]
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'Dữ liệu không hợp lệ'}), 400

    charge_logs = data.get('chargeLogs', [])
    vehicle_id = data.get('vehicleId', '')

    try:
        patterns = pattern_analyzer.analyze(charge_logs)
        patterns['vehicleId'] = vehicle_id
        patterns['analyzedAt'] = datetime.now().isoformat()

        return jsonify({'success': True, 'data': patterns})

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Lỗi phân tích: {str(e)}',
        }), 500


# =============================================================================
# RUN SERVER
# =============================================================================

if __name__ == '__main__':
    print('\n🔋 VinFast Battery — AI Prediction API')
    print('📡 Endpoints:')
    print('   POST /api/predict-degradation')
    print('   POST /api/analyze-patterns')
    print('   GET  /api/health')
    print(f'🌐 http://localhost:5001\n')
    app.run(debug=True, host='0.0.0.0', port=5001)
