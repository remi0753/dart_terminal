#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

EXPECTED_REPLY_HEX = "1b5b3f313b312479"
INPUT_HEX = "1b5b3f31681b5b3f312470"
MAXIMUM_FILE_BYTES = 512 * 1024 * 1024


def regular_file(value):
    path = pathlib.Path(value)
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise argparse.ArgumentTypeError("path must be an absolute regular file")
    if path.stat().st_size <= 0 or path.stat().st_size > MAXIMUM_FILE_BYTES:
        raise argparse.ArgumentTypeError("file size is outside the limit")
    return path


def parse_arguments():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--xterm", type=regular_file, required=True)
    parser.add_argument("--xvfb", type=regular_file, required=True)
    parser.add_argument("--probe", type=regular_file, required=True)
    parser.add_argument("--config", type=regular_file, required=True)
    parser.add_argument("--result-dir", required=True)
    parser.add_argument("--expected-executable-sha256", required=True)
    parser.add_argument("--expected-config-sha256", required=True)
    arguments = parser.parse_args()
    if not pathlib.Path(arguments.result_dir).is_absolute():
        parser.error("result-dir must be absolute")
    for digest in (
        arguments.expected_executable_sha256,
        arguments.expected_config_sha256,
    ):
        if len(digest) != 64 or any(value not in "0123456789abcdef" for value in digest):
            parser.error("expected hash is invalid")
    return arguments


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def terminate(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def main():
    arguments = parse_arguments()
    if sha256(arguments.xterm) != arguments.expected_executable_sha256:
        raise RuntimeError("xterm executable SHA-256 differs")
    if sha256(arguments.config) != arguments.expected_config_sha256:
        raise RuntimeError("xterm configuration SHA-256 differs")
    version = subprocess.run(
        [str(arguments.xterm), "-version"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=5,
    )
    if version.stdout.decode("utf-8", "strict").strip() != "XTerm(411)":
        raise RuntimeError("xterm version differs")

    result_directory = pathlib.Path(arguments.result_dir)
    result_directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    result = result_directory / "probe.json"
    display = ":97"
    xvfb = None
    xterm = None
    try:
        xvfb = subprocess.Popen(
            [
                str(arguments.xvfb),
                display,
                "-screen",
                "0",
                "800x600x24",
                "-nolisten",
                "tcp",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        socket = pathlib.Path("/tmp/.X11-unix/X97")
        deadline = time.monotonic() + 5
        while not socket.exists() and time.monotonic() < deadline:
            if xvfb.poll() is not None:
                raise RuntimeError("Xvfb exited during startup")
            time.sleep(0.02)
        if not socket.exists():
            raise RuntimeError("Xvfb startup timed out")
        environment = dict(os.environ)
        environment.update(
            {
                "DISPLAY": display,
                "XENVIRONMENT": str(arguments.config),
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
            }
        )
        xterm = subprocess.Popen(
            [
                str(arguments.xterm),
                "-geometry",
                "10x4",
                "-u8",
                "-e",
                sys.executable,
                str(arguments.probe),
                "--result=" + str(result),
                "--input-hex=" + INPUT_HEX,
                "--deadline-ms=1600",
                "--quiet-ms=100",
            ],
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 10
        while not result.exists() and time.monotonic() < deadline:
            if xterm.poll() is not None:
                raise RuntimeError("xterm exited before probe capture")
            time.sleep(0.02)
        if not result.exists():
            raise RuntimeError("xterm probe capture timed out")
        if result.stat().st_size > 32 * 1024:
            raise RuntimeError("probe result is too large")
        observation = json.loads(result.read_text(encoding="utf-8"))
        if set(observation) != {
            "format",
            "version",
            "status",
            "terminal_rows",
            "terminal_columns",
            "replies_hex",
        }:
            raise RuntimeError("probe result fields differ")
        if (
            observation["format"] != "dart-terminal-differential-probe"
            or observation["version"] != 1
            or observation["status"] != "ok"
            or observation["terminal_rows"] < 4
            or observation["terminal_columns"] < 10
            or observation["replies_hex"] != EXPECTED_REPLY_HEX
        ):
            raise RuntimeError("xterm probe observation differs")
        print(
            "TERMINAL_DIFFERENTIAL_ADAPTER_SELF_TEST_PASS "
            "backend=xterm-411-linux-aarch64 product=xterm replies=8"
        )
        return 0
    finally:
        terminate(xterm)
        terminate(xvfb)


if __name__ == "__main__":
    raise SystemExit(main())
