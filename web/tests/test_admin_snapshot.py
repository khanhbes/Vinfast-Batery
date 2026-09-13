from server import _admin_snapshot_selection


def test_default_snapshot_excludes_explorer_collection_groups():
    selected, accounts = _admin_snapshot_selection(None)
    assert accounts is True
    assert {'profiles', 'vehicles', 'chargeLogs', 'tripLogs'}.issubset(selected)
    assert 'smartChargeTelemetry' not in selected


def test_single_dataset_and_accounts_projection_are_supported():
    selected, accounts = _admin_snapshot_selection('vehicleSpecs,accounts')
    assert selected == ['profiles', 'vehicleSpecs']
    assert accounts is True


def test_unknown_dataset_is_rejected_without_reading_firestore():
    try:
        _admin_snapshot_selection('vehicles,not-a-real-dataset')
    except ValueError as exc:
        assert 'not-a-real-dataset' in str(exc)
    else:
        raise AssertionError('unknown datasets must be rejected')
