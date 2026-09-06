#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time

MAXIMUM_FILE_BYTES = 512 * 1024 * 1024
MAXIMUM_CASES = 128
MAXIMUM_INPUT_BYTES = 16 * 1024


def regular_file(value):
    path = pathlib.Path(value)
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise argparse.ArgumentTypeError("path must be an absolute regular file")
    if path.stat().st_size <= 0 or path.stat().st_size > MAXIMUM_FILE_BYTES:
        raise argparse.ArgumentTypeError("file size is outside the limit")
    return path


def digest(value):
    if len(value) != 64 or any(byte not in "0123456789abcdef" for byte in value):
        raise argparse.ArgumentTypeError("expected hash is invalid")
    return value


def parse_arguments():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--xterm", type=regular_file, required=True)
    parser.add_argument("--xvfb", type=regular_file, required=True)
    parser.add_argument("--probe", type=regular_file, required=True)
    parser.add_argument("--config", type=regular_file, required=True)
    parser.add_argument("--corpus", type=regular_file, required=True)
    parser.add_argument("--result-dir", required=True)
    parser.add_argument("--expected-executable-sha256", type=digest, required=True)
    parser.add_argument("--expected-config-sha256", type=digest, required=True)
    parser.add_argument("--expected-corpus-sha256", type=digest, required=True)
    arguments = parser.parse_args()
    if not pathlib.Path(arguments.result_dir).is_absolute():
        parser.error("result-dir must be absolute")
    return arguments


def sha256(path):
    digest_value = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest_value.update(chunk)
    return digest_value.hexdigest()


def load_cases(path):
    if path.stat().st_size > 1024 * 1024:
        raise RuntimeError("corpus is too large")
    root = json.loads(path.read_text(encoding="utf-8"))
    if set(root) != {
        "format",
        "version",
        "scope",
        "observation_version",
        "cases",
    }:
        raise RuntimeError("corpus fields differ")
    if (
        root["format"] != "dart-terminal-black-box-differential"
        or root["version"] != 1
        or root["scope"] != "reviewed-corpus"
        or root["observation_version"] != 1
        or not isinstance(root["cases"], list)
        or not 1 <= len(root["cases"]) <= MAXIMUM_CASES
    ):
        raise RuntimeError("corpus identity differs")
    cases = []
    previous_id = ""
    for value in root["cases"]:
        if set(value) != {
            "id",
            "description",
            "inventory_ids",
            "input_hex",
            "rows",
            "columns",
            "fields",
            "expectation",
            "gap_owner",
        }:
            raise RuntimeError("case fields differ")
        case_id = value["id"]
        if (
            not isinstance(case_id, str)
            or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", case_id)
            or (previous_id and previous_id >= case_id)
        ):
            raise RuntimeError("case id differs")
        previous_id = case_id
        compact_hex = "".join(value["input_hex"].split())
        if (
            len(compact_hex) > MAXIMUM_INPUT_BYTES * 2
            or len(compact_hex) % 2
            or not re.fullmatch(r"[0-9a-f]+", compact_hex)
            or not isinstance(value["rows"], int)
            or not 1 <= value["rows"] <= 256
            or not isinstance(value["columns"], int)
            or not 1 <= value["columns"] <= 512
            or value["rows"] * value["columns"] > 65536
        ):
            raise RuntimeError("case bounds differ")
        cases.append(
            {
                "id": case_id,
                "input_hex": compact_hex,
                "rows": value["rows"],
                "columns": value["columns"],
            }
        )
    return cases


def terminate(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def validate_probe(path, test_case):
    if path.stat().st_size > 32 * 1024:
        raise RuntimeError("probe result is too large")
    observation = json.loads(path.read_text(encoding="utf-8"))
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
        or observation["terminal_rows"] < test_case["rows"]
        or observation["terminal_columns"] < test_case["columns"]
        or not re.fullmatch(r"(?:[0-9a-f]{2})*", observation["replies_hex"])
        or len(observation["replies_hex"]) > 8192
    ):
        raise RuntimeError("probe result differs")


def main():
    arguments = parse_arguments()
    for path, expected in (
        (arguments.xterm, arguments.expected_executable_sha256),
        (arguments.config, arguments.expected_config_sha256),
        (arguments.corpus, arguments.expected_corpus_sha256),
    ):
        if sha256(path) != expected:
            raise RuntimeError("input SHA-256 differs")
    version = subprocess.run(
        [str(arguments.xterm), "-version"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=5,
    )
    if version.stdout.decode("utf-8", "strict").strip() != "XTerm(411)":
        raise RuntimeError("xterm version differs")
    cases = load_cases(arguments.corpus)
    result_directory = pathlib.Path(arguments.result_dir)
    result_directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    display = ":97"
    xvfb = None
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
            stderr=subprocess.DEVNULL,
        )
        socket = pathlib.Path("/tmp/.X11-unix/X97")
        deadline = time.monotonic() + 5
        while not socket.exists() and time.monotonic() < deadline:
            if xvfb.poll() is not None:
                raise RuntimeError("Xvfb exited during startup")
            time.sleep(0.02)
        if not socket.exists():
            raise RuntimeError("Xvfb startup timed out")
        for test_case in cases:
            result = result_directory / (test_case["id"] + ".probe.json")
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
                    str(test_case["columns"]) + "x" + str(test_case["rows"]),
                    "-u8",
                    "-e",
                    sys.executable,
                    str(arguments.probe),
                    "--result=" + str(result),
                    "--input-hex=" + test_case["input_hex"],
                    "--deadline-ms=1600",
                    "--quiet-ms=100",
                ],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                deadline = time.monotonic() + 10
                while not result.exists() and time.monotonic() < deadline:
                    if xterm.poll() is not None:
                        raise RuntimeError("xterm exited before probe capture")
                    time.sleep(0.02)
                if not result.exists():
                    raise RuntimeError("xterm probe capture timed out")
                validate_probe(result, test_case)
            finally:
                terminate(xterm)
        print(
            "TERMINAL_DIFFERENTIAL_CAPTURE_PASS "
            "backend=xterm-411-linux-aarch64 cases=" + str(len(cases))
        )
        return 0
    finally:
        terminate(xvfb)


if __name__ == "__main__":
    raise SystemExit(main())
