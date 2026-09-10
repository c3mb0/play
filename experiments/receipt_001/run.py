#!/usr/bin/env python3
"""Bounded external fault injection; receipt creation and recovery run in Erlang."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/gate_001"))
from reference import now, write_json, seal, digest


def main():
    run = ROOT / "receipts" / ("receipt-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    deadline = time.monotonic() + 60
    manifest = dict(start=now(), retries=0, deadline_seconds=60, cases=[],
                    source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip())
    def bound():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("receipt experiment exceeded 60 seconds")
        return min(10, remaining)

    def beam_args(expression, **environment):
        env = os.environ.copy()
        env.update({k: str(v) for k, v in environment.items()})
        args = ["erl", "-noshell", "-pa", str(ROOT / "erlang/pty_lab/_build/default/lib/pty_lab/ebin"),
                "-eval", f'try {expression} of ok -> halt(0) catch C:R:S -> io:format("~p:~p~n~p~n", [C,R,S]), halt(1) end.']
        return args, env

    def invoke(name, expression, **env):
        args, environment = beam_args(expression, **env)
        result = subprocess.run(args, env=environment, cwd=ROOT, capture_output=True, timeout=bound())
        (run / (name + ".stdout")).write_bytes(result.stdout)
        (run / (name + ".stderr")).write_bytes(result.stderr)
        return result.returncode

    def recover(name, source, classification, integrity, metadata=None):
        before = source.read_bytes()
        seal_file = Path(str(source) + ".sha256")
        seal_before = seal_file.read_bytes() if seal_file.exists() else None
        destination = run / (name + "-recovered")
        code = invoke(name, 'receipt_experiment:recover(os:getenv("SOURCE"), os:getenv("DESTINATION"))',
                      SOURCE=source, DESTINATION=destination)
        assert code == 0, (name, code)
        report = json.loads((destination / "recovery.json").read_text())
        analysis = report["analysis"]
        assert analysis["classification"] == classification, (name, analysis)
        assert analysis["integrity"] == integrity, (name, analysis)
        if metadata is not None:
            assert analysis["metadata_complete"] == metadata
        assert source.read_bytes() == before
        assert (destination / "snapshot.jsonl").read_bytes() == before
        assert report["raw_sha256"].lower() == hashlib.sha256(before).hexdigest()
        if seal_before is not None:
            assert seal_file.read_bytes() == seal_before
            assert (destination / "source.sha256").read_bytes() == seal_before
        else:
            assert not seal_file.exists()
        manifest["cases"].append(dict(name=name, outcome="pass", analysis=analysis))
        return destination, report

    try:
        code = invoke("normal-capture", 'receipt_experiment:capture(os:getenv("ROOT"), os:getenv("DIRECTORY"), "normal")',
                      ROOT=ROOT, DIRECTORY=run)
        assert code == 0, "normal capture failed"
        normal = run / "normal.jsonl"
        normal_bytes = normal.read_bytes()
        entries = [json.loads(line) for line in normal_bytes.splitlines()]
        header = entries[0]["data"]
        assert header["receipt_schema"] == 2
        assert header["run_id"] == run.name
        for kind in ["executable", "helper"]:
            fingerprint = header[kind]
            assert digest(Path(fingerprint["path"])) == fingerprint["sha256"].lower()
        assert header["helper"]["reported"]["helper_version"] == "0.3.0"
        fields = bytearray()
        for key, value in sorted(header["spec"]["environment"].items()):
            for field in (key, value):
                raw = field.encode("utf-8")
                fields.extend(struct.pack(">I", len(raw)))
                fields.extend(raw)
        assert hashlib.sha256(fields).hexdigest() == header["environment_sha256"].lower()
        assert header["platform"]["otp_release"]
        assert header["erlang_modules"]["receipt_writer"]
        assert any(e["event"] == "helper_event" and e["data"]["event"] == "child_exit" for e in entries)
        destination, _ = recover("normal", normal, "complete", "verified", True)

        # Prove that a relocated journal + seal is sufficient, without a run manifest.
        detached = run / "detached"
        detached.mkdir()
        shutil.copyfile(normal, detached / "session.jsonl")
        shutil.copyfile(Path(str(normal) + ".sha256"), detached / "session.jsonl.sha256")
        recover("detached", detached / "session.jsonl", "complete", "verified", True)

        args, env = beam_args('receipt_experiment:capture(os:getenv("ROOT"), os:getenv("DIRECTORY"), "interrupt")', ROOT=ROOT, DIRECTORY=run)
        process = subprocess.Popen(args, env=env, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            armed = run / "armed.json"
            armed_deadline = time.monotonic() + bound()
            while not armed.exists():
                if process.poll() is not None or time.monotonic() >= armed_deadline:
                    raise TimeoutError("BEAM did not arm fault injection")
                time.sleep(0.01)
            # Published by a hard link only after the marker and journal are synced.
            marker = json.loads(armed.read_text())
            assert int(marker["beam_pid"]) == process.pid
            pids = [marker[k] for k in ["helper_pid", "guardian_pid", "pid"]]
            for pid in pids:
                os.kill(pid, 0)
            manifest["fault"] = dict(kind="BEAM_SIGKILL", beam_pid=process.pid, pids=pids, unix_ns=time.time_ns())
            process.kill()
            stdout, stderr = process.communicate(timeout=bound())
            assert process.returncode == -signal.SIGKILL
            manifest["fault"]["beam_returncode"] = process.returncode
            cleanup_deadline = time.monotonic() + 3
            while True:
                alive = []
                for pid in pids:
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        pass
                    else:
                        alive.append(pid)
                if not alive:
                    break
                if time.monotonic() >= cleanup_deadline:
                    raise AssertionError(f"processes remain: {alive}")
                time.sleep(0.01)
            manifest["fault"]["all_pids_absent"] = True
        finally:
            if process.poll() is None:
                process.kill()
            stdout, stderr = process.communicate(timeout=bound())
            (run / "interrupt.stdout").write_bytes(stdout)
            (run / "interrupt.stderr").write_bytes(stderr)
        partial = run / "interrupt.jsonl"
        recovered, report = recover("interrupted", partial, "incomplete", "absent", True)
        assert report["analysis"]["outcome"] == "unknown"
        assert report["analysis"]["observed_terminal"] is None
        assert not any(json.loads(line)["event"] == "session_terminal" for line in partial.read_bytes().splitlines())

        # Synthetic boundary fixtures derived from the new complete journal.
        fixtures = run / "synthetic"
        fixtures.mkdir()
        lines = normal_bytes.splitlines(keepends=True)
        skipped = json.loads(lines[1]); skipped["seq"] += 1
        changed = json.loads(lines[1]); changed["identity"]["session"] = "other"
        bad_env = json.loads(lines[0]); bad_env["data"]["environment_sha256"] = "0" * 64
        cases = {
            "empty": (b"", "incomplete"),
            "torn-tail": (partial.read_bytes() + b'{"seq":', "incomplete"),
            "unsealed-complete": (normal_bytes, "complete"),
            "invalid-middle": (lines[0] + b"invalid\n" + b"".join(lines[1:]), "quarantined"),
            "sequence-gap": (lines[0] + json.dumps(skipped).encode() + b"\n" + b"".join(lines[2:]), "quarantined"),
            "identity-change": (lines[0] + json.dumps(changed).encode() + b"\n" + b"".join(lines[2:]), "quarantined"),
            "after-terminal": (normal_bytes + b"partial", "quarantined"),
            "environment-mismatch": (json.dumps(bad_env).encode() + b"\n" + b"".join(lines[1:]), "quarantined"),
        }
        for name, (data, expected) in cases.items():
            source = fixtures / (name + ".jsonl")
            source.write_bytes(data)
            recover(name, source, expected, "absent")
        for name, seal_bytes, expected in [("wrong-seal", b"0" * 64, "mismatch"), ("malformed-seal", b"nope", "malformed")]:
            source = fixtures / (name + ".jsonl")
            source.write_bytes(normal_bytes)
            Path(str(source) + ".sha256").write_bytes(seal_bytes)
            recover(name, source, "quarantined", expected)
        before = {p.name: digest(p) for p in recovered.iterdir()}
        code = invoke("destination-reuse", 'receipt_experiment:recover(os:getenv("SOURCE"), os:getenv("DESTINATION"))',
                      SOURCE=partial, DESTINATION=recovered)
        assert code != 0
        assert before == {p.name: digest(p) for p in recovered.iterdir()}
        manifest["cases"].append(dict(name="destination-reuse", outcome="pass", operation="rejected without mutation"))
        manifest["outcome"] = "pass"
    except Exception as error:
        manifest.update(outcome="failed", error=repr(error))
        raise
    finally:
        manifest["end"] = now()
        write_json(run / "manifest.json", manifest)
        seal(run)
        print(run)


if __name__ == "__main__":
    main()
