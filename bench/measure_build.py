#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        temporary = pathlib.Path(directory)
        prefix = temporary / "prefix"
        started = time.perf_counter_ns()
        subprocess.run(
            [
                "zig",
                "build",
                "-Doptimize=ReleaseSafe",
                "--cache-dir",
                str(temporary / "cache"),
                "--prefix",
                str(prefix),
            ],
            cwd=ROOT,
            env={**os.environ, "ZIG_GLOBAL_CACHE_DIR": str(temporary / "global-cache")},
            check=True,
        )
        elapsed = time.perf_counter_ns() - started
        print(
            json.dumps(
                {
                    "clean_release_build_ns": elapsed,
                    "launcher_bytes": (prefix / "bin/zig-tool").stat().st_size,
                    "project_backend_bytes": (prefix / "bin/zig-tool-backend").stat().st_size,
                },
                separators=(",", ":"),
            )
        )


if __name__ == "__main__":
    main()
