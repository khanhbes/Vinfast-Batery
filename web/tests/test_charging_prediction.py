"""Tests for /api/ai/predict-charging-time endpoint strictAi and guardrails."""
import pytest
from unittest.mock import patch
import sys
import os

# Ensure web dir is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from server import app, _heuristic_predict_charging_time


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


def test_charging_prediction_strict_ai_success(client):
    """When AI model succeeds and passes guardrails, strictAi=True returns 200 with modelSource='ai_model'."""
    heur = _heuristic_predict_charging_time(20, 80)
    matching_sec = heur['predictedDurationSec']
    ai_mock_data = {
        'predictedDurationSec': matching_sec,
        'predictedDurationMin': matching_sec / 60.0,
        'formattedDuration': heur['formattedDuration'],
        'modelVersion': 'v1.0.0',
        'rawPrediction': matching_sec,
        'processedInput': {},
        'chartData': None,
        'warnings': [],
    }
    
    with patch('server._ai_predict_charging_time', return_value=(ai_mock_data, True)):
        resp = client.post('/api/ai/predict-charging-time', json={
            'vehicleId': 'test_veh',
            'currentBattery': 20,
            'targetBattery': 80,
            'strictAi': True,
        })
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['success'] is True
        assert data['data']['modelSource'] == 'ai_model'
        assert data['data']['predictedDurationSec'] == matching_sec


def test_charging_prediction_strict_ai_unavailable_returns_503(client):
    """When AI model is unavailable or fails, strictAi=True returns 503 AI_MODEL_UNAVAILABLE."""
    with patch('server._ai_predict_charging_time', return_value=(None, False)):
        resp = client.post('/api/ai/predict-charging-time', json={
            'vehicleId': 'test_veh',
            'currentBattery': 20,
            'targetBattery': 80,
            'strictAi': True,
        })
        assert resp.status_code == 503
        data = resp.get_json()
        assert data['success'] is False
        assert data['debugCode'] == 'AI_MODEL_UNAVAILABLE'
        assert 'chưa khả dụng' in data['error']


def test_charging_prediction_strict_ai_guardrail_returns_422(client):
    """When AI model succeeds but guardrail rejects deviation, strictAi=True returns 422."""
    ai_mock_data = {
        'predictedDurationSec': 200.0,  # < 300s -> guardrail too short!
        'predictedDurationMin': 3.33,
        'formattedDuration': '3 phút',
        'modelVersion': 'v1.0.0',
        'warnings': [],
    }
    with patch('server._ai_predict_charging_time', return_value=(ai_mock_data, True)):
        resp = client.post('/api/ai/predict-charging-time', json={
            'vehicleId': 'test_veh',
            'currentBattery': 20,
            'targetBattery': 80,
            'strictAi': True,
        })
        assert resp.status_code == 422
        data = resp.get_json()
        assert data['success'] is False
        assert data['debugCode'] == 'AI_PREDICTION_REJECTED'
        assert data['debugDetail'] == 'heuristic_guardrail_too_short'


def test_charging_prediction_non_strict_keeps_heuristic_fallback(client):
    """When strictAi=False, AI failure falls back to heuristic and returns 200."""
    with patch('server._ai_predict_charging_time', return_value=(None, False)):
        resp = client.post('/api/ai/predict-charging-time', json={
            'vehicleId': 'test_veh',
            'currentBattery': 20,
            'targetBattery': 80,
            'strictAi': False,
        })
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['success'] is True
        assert data['data']['modelSource'] == 'heuristic_fallback'
