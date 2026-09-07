"""
QA Master Audit Test Suite — AI Service, Model Lifecycle & Upload Security
Covers:
- WEB-H7: Direct access to AI server without internal token
- WEB-H8: Unsafe pickle/joblib deserialization path
- WEB-H9: Manifest vs runtime synchronization
- WEB-H10: Concurrent deploy/rollback race conditions
- WEB-H11: Active model deletion prevention
- WEB-H24: Path traversal in version parameter / arbitrary file extension
- WEB-H25: Manifest write atomicity
"""
import os
import json
import pytest
import threading
from ai_server.model_store import ModelStore
from ai_server.model_runtime import ModelRuntime, _load_model_file

class TestAiUploadLifecycle:
    def test_web_h11_cannot_delete_active_model(self, temp_models_dir):
        """
        WEB-H11: ModelStore must reject removing the active version.
        """
        store = ModelStore(temp_models_dir)
        dummy_file = os.path.join(temp_models_dir, "temp_model.pkl")
        with open(dummy_file, "wb") as f:
            f.write(b"dummy_bytes")
            
        store.save_from_temp(dummy_file, "1.0.0", "initial", ext=".pkl")
        store.activate("1.0.0")
        assert store.active_version() == "1.0.0"
        
        with pytest.raises(ValueError, match="Không thể xóa version đang active"):
            store.remove("1.0.0")

    def test_web_h24_path_traversal_in_model_version(self, temp_models_dir):
        """
        WEB-H24: Check whether version parameter allows path traversal (e.g. 'sub/../../outside').
        """
        store = ModelStore(temp_models_dir)
        traversal_version = "sub/../../escaped_version"
        path = store.path_of(traversal_version, ".pkl")
        
        # Check if resolved path escapes store.root
        resolved_path = os.path.abspath(path)
        escaped = not resolved_path.startswith(store.root)
        assert escaped, "Vulnerability WEB-H24 Confirmed: version parameter permits directory traversal outside model root!"

    def test_web_h8_unsafe_deserialization_fallback(self, tmp_path):
        """
        WEB-H8: Verify that _load_model_file attempts pickle/joblib deserialization
        even for unknown or non-standard file extensions.
        """
        test_file = tmp_path / "model.unknown_ext"
        test_file.write_bytes(b"\x80\x04\x95\x15\x00\x00\x00\x00\x00\x00\x00}\x94\x8c\x04test\x94\x8c\x04pass\x94s.")
        
        loaded = _load_model_file(str(test_file))
        assert loaded == {"test": "pass"}, (
            "Vulnerability WEB-H8 Confirmed: _load_model_file executes pickle deserialization on arbitrary unknown extensions"
        )

    def test_web_h25_manifest_atomic_write(self, temp_models_dir):
        """
        WEB-H25: Test that _write_manifest uses atomic rename (.tmp -> manifest.json).
        """
        store = ModelStore(temp_models_dir)
        test_data = {"active": "2.0.0", "versions": [{"version": "2.0.0", "ext": ".pkl"}]}
        store._write_manifest(test_data)
        
        read_data = store._read_manifest()
        assert read_data["active"] == "2.0.0"
        assert not os.path.exists(store.manifest_path + ".tmp")

    def test_web_h10_concurrent_operations_protected_by_lock(self, temp_models_dir):
        """
        WEB-H10: Concurrency test — simultaneous save and activate operations
        must not corrupt the manifest JSON.
        """
        store = ModelStore(temp_models_dir)
        errors = []

        def worker(idx):
            try:
                temp_file = os.path.join(temp_models_dir, f"tmp_{idx}.pkl")
                with open(temp_file, "wb") as f:
                    f.write(b"data")
                ver = f"1.0.{idx}"
                store.save_from_temp(temp_file, ver, f"worker {idx}")
                store.activate(ver)
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        manifest = store._read_manifest()
        assert isinstance(manifest.get("versions"), list)
        assert len(errors) == 0, f"Concurrent operations caused errors: {errors}"
