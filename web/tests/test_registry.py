import pytest
from ai_server.registry import MODEL_TYPES, list_types, list_groups, get_type, known_keys


def test_known_keys_contains_nine_models():
    keys = known_keys()
    assert len(keys) == 9
    expected = [
        "soc", "dte", "eco_driving", "eco_routing", "charging_time",
        "charging_recommender", "trip_labeling", "soh_degradation", "anomaly_detection"
    ]
    for k in expected:
        assert k in keys


def test_model_types_metadata_completeness():
    for key, model in MODEL_TYPES.items():
        assert model["key"] == key
        assert model["label"]
        assert model["shortName"]
        assert model["description"]
        assert model["group"] in ["survival", "assistant", "health"]
        assert model["phase"] in ["v1.0", "v2.0", "v3.0"]
        assert model["status"] in ["ready", "in_progress", "planned"]
        assert model["icon"]
        assert model["accent"] in ["emerald", "amber", "violet", "blue", "rose", "slate"]
        assert model["output_kind"] in ["scalar", "vector", "class"]
        assert isinstance(model["input_fields"], list)
        assert len(model["input_fields"]) > 0
        assert isinstance(model["smoke_input"], dict)
        
        # Test visible fields subset
        visible = model.get("visible_input_fields")
        if visible:
            for vf in visible:
                assert vf in model["input_fields"]

        # Test derived fields validity
        derived = model.get("derived_fields")
        if derived:
            for df, df_spec in derived.items():
                assert df in model["input_fields"]
                for dep in df_spec.get("from", []):
                    assert dep in model["input_fields"]

        # Test input_schema
        schema = model.get("input_schema")
        if schema:
            for sf, spec in schema.items():
                assert sf in model["input_fields"]
                assert spec["type"] in ["string", "integer", "number"]
                if "min" in spec and "max" in spec:
                    assert spec["min"] <= spec["max"]


def test_dte_contract():
    dte = get_type("dte")
    assert dte["outputUnit"] == "km"
    assert dte["display_unit"] == "distance"
    expected_fields = [
        "batteryPercent", "stateOfHealth", "temperatureC",
        "averageSpeedKmh", "payloadKg", "baseEfficiencyKmPerPercent"
    ]
    for f in expected_fields:
        assert f in dte["input_fields"]
        assert f in dte["smoke_input"]


def test_list_types_structure():
    types = list_types()
    assert len(types) == 9
    for t in types:
        assert "key" in t
        assert "inputSchema" in t
        assert "sampleInput" in t
        assert "outputKind" in t
        assert "displayUnit" in t
