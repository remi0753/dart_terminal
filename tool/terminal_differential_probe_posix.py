#!/usr/bin/env python3
import argparse
import json
import os
import select
import sys
import termios
import time
import tty

MAXIMUM_INPUT_BYTES = 16 * 1024
MAXIMUM_REPLY_BYTES = 4096


def parse_arguments():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--result", required=True)
    parser.add_argument("--input-hex", required=True)
    parser.add_argument("--deadline-ms", required=True, type=int)
    parser.add_argument("--quiet-ms", required=True, type=int)
    arguments = parser.parse_args()
    if not arguments.result.startswith("/"):
        raise ValueError("result must be absolute")
    if not 100 <= arguments.deadline_ms <= 5000:
        raise ValueError("deadline is outside the limit")
    if not 10 <= arguments.quiet_ms < arguments.deadline_ms:
        raise ValueError("quiet period is outside the limit")
    if len(arguments.input_hex) > MAXIMUM_INPUT_BYTES * 2:
        raise ValueError("input exceeds the limit")
    terminal_input = bytes.fromhex(arguments.input_hex)
    return arguments, terminal_input


def main():
    try:
        arguments, terminal_input = parse_arguments()
    except (ValueError, SystemExit):
        return 64
    input_fd = sys.stdin.fileno()
    output_fd = sys.stdout.fileno()
    has_terminal = os.isatty(input_fd) and os.isatty(output_fd)
    rows = 0
    columns = 0
    replies = bytearray()
    status = "not-a-terminal"
    original = None
    try:
        if has_terminal:
            terminal_size = os.get_terminal_size(output_fd)
            rows = terminal_size.lines
            columns = terminal_size.columns
            original = termios.tcgetattr(input_fd)
            tty.setraw(input_fd)
            os.write(output_fd, terminal_input)
            deadline = time.monotonic() + arguments.deadline_ms / 1000.0
            quiet_deadline = None
            while time.monotonic() < deadline:
                remaining = deadline - time.monotonic()
                if quiet_deadline is not None:
                    remaining = min(remaining, quiet_deadline - time.monotonic())
                    if remaining <= 0:
                        break
                readable, _, _ = select.select([input_fd], [], [], remaining)
                if not readable:
                    if quiet_deadline is not None:
                        break
                    continue
                chunk = os.read(input_fd, MAXIMUM_REPLY_BYTES + 1)
                if len(replies) + len(chunk) > MAXIMUM_REPLY_BYTES:
                    status = "overflow"
                    break
                replies.extend(chunk)
                quiet_deadline = time.monotonic() + arguments.quiet_ms / 1000.0
            else:
                status = "ok"
            if status != "overflow":
                status = "ok"
    except OSError:
        status = "overflow"
    finally:
        if original is not None:
            try:
                termios.tcsetattr(input_fd, termios.TCSANOW, original)
            except termios.error:
                pass
    result = {
        "format": "dart-terminal-differential-probe",
        "version": 1,
        "status": status,
        "terminal_rows": rows,
        "terminal_columns": columns,
        "replies_hex": replies.hex(),
    }
    partial = arguments.result + ".partial"
    with open(partial, "x", encoding="utf-8") as output:
        json.dump(result, output, separators=(",", ":"), sort_keys=True)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(partial, arguments.result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
