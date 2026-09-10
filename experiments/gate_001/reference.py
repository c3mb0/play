#!/usr/bin/env python3
"""One-shot Phase A capture. No helper code is used here (macOS only)."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "TERM": "xterm-256color"}
SCRATCH = ROOT / "experiments/gate_001/scratch"
SNAPSHOT = SCRATCH / "observation.json"
ARGV = [str(ROOT / "target/debug/topology_probe"), "--snapshot", str(SNAPSHOT)]


def now():
    return datetime.now(timezone.utc).isoformat()


def write_json(file, value):
    with file.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def seal(directory):
    write_json(directory / "SHA256.json", {
        str(p.relative_to(directory)): digest(p)
        for p in sorted(directory.rglob("*")) if p.is_file()
    })
    for p in directory.rglob("*"):
        if p.is_file():
            p.chmod(0o444)


def main():
    run = ROOT / "receipts" / ("reference-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    SCRATCH.mkdir(exist_ok=True)
    if SNAPSHOT.exists():
        raise RuntimeError("existing snapshot requires inspection; refusing overwrite")
    manifest = dict(schema=1, kind="pre-harness-reference", start=now(),
                    platform=platform.platform(), argv=ARGV, cwd=str(ROOT),
                    environment=ENV, environment_sha256=hashlib.sha256(
                        json.dumps(ENV, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                    executable_sha256=digest(Path(ARGV[0])),
                    source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                    input_hex="", timeout_seconds=10, retries=0,
                    protocol_version=None, helper_version=None, cells=[])
    try:
        start = now()
        result = subprocess.run(ARGV, cwd=ROOT, env=ENV, input=b"", capture_output=True,
                                start_new_session=True, timeout=10)
        (run / "pipe.stdout").write_bytes(result.stdout)
        (run / "pipe.stderr").write_bytes(result.stderr)
        manifest["cells"].append(dict(cell="pipe", start=start, end=now(), exit_code=result.returncode))
        if result.returncode:
            raise RuntimeError("pipe probe failed")
        SNAPSHOT.rename(run / "pipe.json")

        # A fresh Terminal window, foreground shell job, all stdio on its terminal.
        done = SCRATCH / "terminal.exit"
        if done.exists():
            raise RuntimeError("existing terminal exit file; refusing overwrite")
        script = SCRATCH / "terminal-reference.sh"
        script.write_text("#!/bin/bash\ncd " + shlex.quote(str(ROOT)) + " || exit 99\n"
                          + "/bin/stty rows 24 cols 80 || exit 98\n"
                          + shlex.join(["/usr/bin/env", "-i"] + [f"{k}={v}" for k, v in ENV.items()] + ARGV)
                          + "\nprintf '%s\\n' \"$?\" > " + shlex.quote(str(done)) + "\n")
        command = shlex.join(["/bin/bash", str(script)])
        apple = 'tell application "Terminal"\nset t to do script ' + json.dumps(command) + '\nreturn id of front window\nend tell'
        start = now()
        launched = subprocess.run(["/usr/bin/osascript", "-e", apple], capture_output=True, timeout=10)
        (run / "terminal-launch.stdout").write_bytes(launched.stdout)
        (run / "terminal-launch.stderr").write_bytes(launched.stderr)
        if launched.returncode:
            raise RuntimeError("Terminal launch failed")
        deadline = time.monotonic() + 10
        while not done.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        if not done.exists():
            raise TimeoutError("Terminal reference exceeded deadline; inspect dedicated window")
        code = int(done.read_text().strip())
        manifest["cells"].append(dict(cell="terminal", start=start, end=now(), exit_code=code,
                                      source="macOS Terminal.app, foreground /bin/bash job",
                                      window_id=launched.stdout.decode().strip(), rows=24, cols=80,
                                      stdout_capture="screen only; side-channel JSON preserved"))
        if code:
            raise RuntimeError("terminal probe failed")
        SNAPSHOT.rename(run / "terminal.json")
        done.rename(run / "terminal.exit")
        (run / "terminal-command.sh").write_bytes(script.read_bytes())
        manifest["outcome"] = "captured"
    except Exception as error:
        manifest["outcome"] = "failed"
        manifest["error"] = repr(error)
        raise
    finally:
        manifest["end"] = now()
        write_json(run / "manifest.json", manifest)
        seal(run)
        print(run)


if __name__ == "__main__":
    main()
