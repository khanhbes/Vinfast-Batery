"""Validate templates with synthetic values; never load the real Compose env."""
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    web = Path(__file__).resolve().parents[1] / "web"
    content = (web / "docker-compose.yml").read_text(encoding="utf-8")
    env = {key: os.environ[key] for key in ("PATH", "SystemRoot", "USERPROFILE", "APPDATA", "LOCALAPPDATA")
           if key in os.environ}
    for key in re.findall(r"\$\{([A-Z0-9_]+):\?", content):
        env[key] = "qa-template-only"
    env["COMPOSE_PROFILES"] = ""
    result = subprocess.run(["docker", "--context", "desktop-linux", "compose",
        "--env-file", ".env.docker.example", "-f", "docker-compose.yml", "config", "--format", "json"],
        cwd=web, env=env, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"template validation failed ({result.returncode})")
    services = json.loads(result.stdout)["services"]
    api, worker = services["api"], services["smart-charge-worker"]
    assert "ai" not in api.get("depends_on", {})
    assert worker["build"]["dockerfile"] == "Dockerfile.worker"
    assert "AI_SERVER_URL" not in worker["environment"]
    assert "AI_SERVER_INTERNAL_TOKEN" not in worker["environment"]
    assert worker["environment"]["AZURE_STAGING_HARDWARE_DISABLED"] == "1"
    assert worker["environment"]["SHELLY_PROVIDER"] == "vault_cloud"
    assert not worker.get("ports") and not worker.get("volumes")
    assert worker["read_only"] and "ALL" in worker["cap_drop"]
    print(json.dumps({"templateOnly": True, "coreApiIndependentOfAi": True,
        "workerStandalone": True, "privateProbe": True, "stagingOnStillLocked": True,
        "realEnvLoaded": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
