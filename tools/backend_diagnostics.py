"""Bounded runner companion: emits phases/stacks, never local variables or env."""
import faulthandler
import sys
import time
from pathlib import Path

started = time.monotonic()
print("backend-diagnostics: python-started", flush=True)
sys.path.insert(0, str(Path.cwd()))
faulthandler.enable()
faulthandler.dump_traceback_later(45, repeat=True)
try:
    import pytest
    print(f"backend-diagnostics: pytest-imported elapsed={time.monotonic() - started:.2f}s", flush=True)
    raise SystemExit(pytest.main(sys.argv[1:]))
finally:
    faulthandler.cancel_dump_traceback_later()
