"""Local offline QA only; touches only the uniquely named container it creates."""
import argparse
import json
import re
import subprocess
import time
import uuid


def docker(*args, timeout=30, check=True):
    result = subprocess.run(["docker", "--context", "desktop-linux", *args],
                            capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f"docker step failed ({result.returncode}): {args[0]}")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", default="102")
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]{1,4}", args.task):
        parser.error("Expected numeric QA task ID")
    image = "vinfast-worker-qa:task" + args.task
    name = "vinfast-worker-qa-" + args.task + "-" + uuid.uuid4().hex[:12]
    label = "vinfast.qa.task=" + args.task
    container = docker("create", "--name", name, "--label", label,
        "--network", "none", "--memory", "512m", "--cpus", "0.25", "--read-only",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
        image, "python", "scripts/worker_fixture_smoke.py", "--hold-seconds", "120").stdout.strip()
    if not re.fullmatch(r"[a-f0-9]{64}", container):
        raise RuntimeError("invalid QA container ID")
    try:
        docker("start", container)
        deadline = time.monotonic() + 30
        first = None
        while time.monotonic() < deadline:
            lines = docker("logs", container).stdout.splitlines()
            if lines:
                first = json.loads(lines[0])
                break
            time.sleep(0.25)
        if not first or not first["ready"] or first["relayCommands"] != 0 or first["forbiddenImports"]:
            raise RuntimeError("fixture readiness failed")
        docker("exec", container, "python", "-m", "shelly.worker_health")
        stats = json.loads(docker("stats", "--no-stream", "--format", "{{json .}}", container).stdout)
        image_record = json.loads(docker("image", "inspect", "--format",
                                         '{{json .}}', image).stdout)
        # No image/container environment or private metadata is printed.
        print(json.dumps({"fixture": first, "imageId": image_record["Id"],
                          "imageSizeBytes": image_record["Size"],
                          "stats": {key: stats[key] for key in ("MemUsage", "MemPerc", "CPUPerc", "PIDs")}}), flush=True)
        # Query package name/version directly; pip's CLI/plugin startup is not
        # part of the runtime probe and was timing out on the constrained host.
        deps = json.loads(docker("exec", container, "python", "-c",
            "import json, importlib.metadata as m; "
            "print(json.dumps(sorted(d.metadata['Name']+'=='+d.version for d in m.distributions())))").stdout)
        print(json.dumps({"dependencyManifest": deps}), flush=True)
        docker("stop", "--time", "15", container)
        exit_code = int(docker("inspect", "--format", "{{.State.ExitCode}}", container).stdout)
        oom = docker("inspect", "--format", "{{.State.OOMKilled}}", container).stdout.strip()
        final = json.loads(docker("logs", container).stdout.splitlines()[-1])
        if exit_code != 0 or oom != "false" or not final["stopped"] or not final["leaseReleased"]:
            raise RuntimeError("fixture graceful shutdown failed")
        print(json.dumps({"shutdown": final, "exitCode": exit_code, "oomKilled": False}), flush=True)
        invalid = docker("run", "--rm", "--network", "none", "--memory", "512m", "--cpus", "0.25",
            "--read-only", "--cap-drop", "ALL", image, check=False)
        if invalid.returncode != 1 or "workerScopeNotConfigured" not in invalid.stdout:
            raise RuntimeError("unconfigured production entry did not fail closed")
        print(json.dumps({"unconfiguredEntryExitCode": invalid.returncode, "startupBlocked": True}), flush=True)
    finally:
        # Only the exact ID created above, with our QA label, may be removed.
        owned = docker("inspect", "--format", '{{index .Config.Labels "vinfast.qa.task"}}',
                       container, check=False)
        if owned.returncode == 0 and owned.stdout.strip() == args.task:
            docker("rm", "--force", container)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
