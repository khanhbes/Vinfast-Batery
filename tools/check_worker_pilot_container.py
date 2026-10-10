"""Bounded offline smoke with exact task-created container cleanup."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--docker", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    image = "vinfast-worker-pilot:task105"
    label = "vinfast.qa.pilot=" + uuid.uuid4().hex
    containers = []
    report = {"passed": False, "mode": "offline_fixture", "hardwareCommands": 0}
    report["sourceHashes"] = {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in ("web/shelly/worker_pilot.py", "web/shelly/profile_vault.py", "web/requirements-worker.txt",
                     "web/Dockerfile.worker-pilot", "web/Dockerfile.worker-pilot.dockerignore",
                     "web/scripts/worker_pilot_fixture.py", "deploy/azure/worker-pilot.bicep")
    }

    def run(*command, timeout=30, check=True):
        result = subprocess.run([args.docker, *command], capture_output=True, text=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError("Docker smoke command failed; no raw diagnostics printed")
        return result

    try:
        report["phase"] = "image_inspect"
        info = json.loads(run("image", "inspect", image).stdout)[0]
        report["imageId"] = info["Id"]
        assert info["Config"]["User"] == "10001"
        assert info["Config"]["Cmd"] == ["python", "-m", "shelly.worker_pilot"]
        cid = run("run", "-d", "--label", label, "--network", "none", "--read-only",
                  "--memory", "512m", "--cpus", "0.25", "--tmpfs", "/tmp:size=8m",
                  "--mount", f"type=bind,source={root / 'web/scripts/worker_pilot_fixture.py'},target=/app/fixture.py,readonly",
                  image, "python", "/app/fixture.py").stdout.strip()
        containers.append(cid)
        report["phase"] = "offline_healthcheck"
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if run("exec", cid, "python", "-m", "shelly.worker_pilot", "--healthcheck", check=False).returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError("Offline health check exceeded its deadline")
        report["healthcheck"] = True
        report["phase"] = "shutdown"
        memory = run("exec", cid, "sh", "-c", "sed -n '/^VmRSS:/p;/^VmHWM:/p' /proc/1/status").stdout.strip()
        report["memory"] = memory
        run("kill", "--signal", "TERM", cid)
        assert run("wait", cid, timeout=15).stdout.strip() == "0"
        state = json.loads(run("inspect", cid).stdout)[0]["State"]
        assert not state["OOMKilled"]
        report["shutdownExitCode"] = state["ExitCode"]
        report["phase"] = "missing_configuration"
        cid2 = run("create", "--label", label, "--network", "none", "--read-only", "--memory", "512m", "--cpus", "0.25", image).stdout.strip()
        containers.append(cid2)
        invalid = run("start", "-a", cid2, check=False)
        state = json.loads(run("inspect", cid2).stdout)[0]["State"]
        assert state["ExitCode"] == 1 and not state["OOMKilled"]
        assert "pilot_start_failed" in invalid.stdout
        report["missingConfigExitCode"] = 1
        report["passed"] = True
        report["phase"] = "complete"
    except Exception as exc:
        report["failureType"] = type(exc).__name__
    finally:
        for cid in containers:
            details = json.loads(run("inspect", cid).stdout)[0]
            assert details["Config"]["Labels"].get("vinfast.qa.pilot") == label.split("=", 1)[1]
            run("rm", "-f", cid)
        Path(args.output).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
