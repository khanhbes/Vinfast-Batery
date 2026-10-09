"""Scoped production-code hygiene and reproducible manifest; never scans env files."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
AREAS = [ROOT / "app/lib", ROOT / "app/pubspec.yaml", ROOT / "app/pubspec.lock",
         ROOT / "web/ai_server/fine_tune.py", ROOT / "web/firestore.rules",
         ROOT / "web/shelly", ROOT / "web/server.py", ROOT / "web/smart_charge_worker.py",
         ROOT / "web/smart_charge_worker_entry.py", ROOT / "web/docker-compose.yml",
         ROOT / "web/Dockerfile.api", ROOT / "web/Dockerfile.worker",
         ROOT / "web/Dockerfile.worker.dockerignore", ROOT / "web/requirements-worker.txt",
         ROOT / "web/scripts/worker_fixture_smoke.py", ROOT / "web/.env.docker.example",
         ROOT / "web/Dockerfile.cloud-dispatch-tests", ROOT / "web/Dockerfile.cloud-dispatch-tests.dockerignore",
         ROOT / "tools/backend_diagnostics.py", ROOT / "tools/run_quality_gate.py", ROOT / "tools/check_worker_container.py",
         *(ROOT / "web/tests" / name for name in (
             "test_cloud_dispatch.py", "test_shelly_live_safety.py", "test_shelly_vault_safety.py",
             "test_smart_charge_worker_lease.py", "test_worker_runtime.py", "test_shelly_membership_emulator.py"))]
PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "literal-secret": re.compile(r'''(?i)(?:cloudAuthKey|auth_key|GEMINI_API_KEY)\s*[:=]\s*["'][a-zA-Z0-9_./+\-=]{24,}["']'''),
    # Vietnamese words such as ĐÃ / NHÂN are NOT broken encoding.
    "mojibake": re.compile(r"Ã[\u0080-\u00bf]|Â[\u0080-\u00bf]|â€[\u0080-\u00bf]|ï¿½"),
}

def main():
    files = sorted({p for area in AREAS for p in (
        (path for path in area.rglob("*") if path.suffix in {".dart", ".py"})
        if area.is_dir() else [area])})
    findings, manifest = [], []
    for path in files:
        payload = path.read_bytes()
        relative = path.relative_to(ROOT).as_posix()
        manifest.append({"path": relative, "sha256": hashlib.sha256(payload).hexdigest()})
        for number, line in enumerate(payload.decode("utf-8").splitlines(), 1):
            for kind, pattern in PATTERNS.items():
                if pattern.search(line):
                    findings.append({"path": relative, "line": number, "kind": kind})
    sha = subprocess.check_output(["git", "-c", f"safe.directory={ROOT.as_posix()}", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    print(json.dumps({"sourceHead": sha, "filesScanned": len(files), "findings": findings,
        "files": manifest, "scope": "app/lib + dependency manifest + training pipeline + Firestore Rules + web/shelly + worker/entry + deployment templates + critical QA harness/fixtures; excludes real env, Git history and APK"}, ensure_ascii=False))
    return 1 if findings else 0

if __name__ == "__main__":
    raise SystemExit(main())
