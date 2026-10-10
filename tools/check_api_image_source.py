"""Verify API image bytes against local allowlisted source; no runtime secrets/network."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
FLAT = (
    "requirements-api.txt", "server.py", "auth_context.py", "deployment_policy.py",
    "telemetry_schema.py", "csv_security.py", "sync_writes.py", "request_limits.py",
    "vehicle_catalog.py", "catalog_research_worker.py", "smart_charge_worker.py",
    "smart_charge_worker_entry.py", "scripts/migrate_vehicle_catalog.py",
    "assets/vinfast_specs_fallback.json",
)
CHECK = r'''
import hashlib,json,pathlib,sys
expected=json.load(sys.stdin)
root=pathlib.Path('/app')
mismatches=[]
for name,digest in expected.items():
    file=root/name
    if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
        mismatches.append(name)
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
unexpected=sorted(actual-set(expected))
print(json.dumps({'filesVerified':len(expected),'mismatches':mismatches,'unexpectedFiles':unexpected}))
sys.exit(1 if mismatches or unexpected else 0)
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--docker", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--qa-image", required=True)
    args = parser.parse_args()
    paths = [WEB / name for name in FLAT]
    paths += list((WEB / "shelly").rglob("*.py"))
    paths += list((WEB / "ai_server").rglob("*.py"))
    expected = {p.relative_to(WEB).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(set(paths))}
    subprocess.run([args.docker, "run", "--rm", "-i", "--network", "none",
                    "--label", "vinfast.azure.qa=api106-source", "--memory", "128m",
                    "--cpus", "0.25", "--entrypoint", "python", args.image,
                    "-c", CHECK], input=json.dumps(expected), text=True, check=True, timeout=90)
    def layers(image):
        result = subprocess.run([args.docker, "image", "inspect", image, "--format",
                                 "{{json .RootFS.Layers}}"], capture_output=True,
                                text=True, check=True, timeout=30)
        return json.loads(result.stdout)
    base, qa = layers(args.image), layers(args.qa_image)
    if qa[:len(base)] != base:
        raise RuntimeError("QA image does not inherit the verified API layers")
    print(json.dumps({"qaInheritsVerifiedApiLayers": True, "apiLayerCount": len(base)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
