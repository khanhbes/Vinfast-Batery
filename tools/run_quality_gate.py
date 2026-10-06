"""Bounded local quality gate; only terminates the process tree it starts."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time


def redact(text):
    """Diagnostic text only. Never pass secrets in command-line arguments."""
    text = re.sub(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}",
                  "[redacted-email]", text, flags=re.IGNORECASE)
    text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b",
                  "[redacted-token]", text)
    text = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[redacted-token]", text)
    return re.sub(
        r'''(?i)(["']?(?:access_token|refresh_token|id_token|password|cloudAuthKey|auth_key|deviceId|ownerUid|userId|uid)["']?\s*[:=]\s*)(["'][^"'\r\n]*["']|[^\s,}\r\n]+)''',
        r'\1"[redacted]"', text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("Missing command")
    log = Path(args.log).resolve()
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    timed_out = False
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(command, cwd=args.cwd, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
        def copy_diagnostics():
            for line in process.stdout:
                # Filter before persistence, including CLI account diagnostics.
                output.write(redact(line))
                output.flush()
        reader = threading.Thread(target=copy_diagnostics, daemon=True)
        reader.start()
        try:
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                process.kill()
            process.wait(timeout=15)
        reader.join(timeout=5)
    result = {"command": [redact(argument) for argument in command], "cwd": args.cwd, "log": str(log),
              "timeoutSeconds": args.timeout, "timedOut": timed_out,
              "exitCode": process.returncode,
              "elapsedSeconds": round(time.monotonic() - started, 2)}
    log.with_suffix(log.suffix + ".result.json").write_text(
        json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))
    return 124 if timed_out else process.returncode


if __name__ == "__main__":
    raise SystemExit(main())
