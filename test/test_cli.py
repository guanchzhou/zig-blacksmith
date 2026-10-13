#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BACKEND = ROOT / "zig-out/bin/zig-tool-backend"


def run(*args: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [BACKEND, *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"{args}: expected exit {expected}, got {result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def main() -> None:
    subprocess.run(["zig", "build", "install"], cwd=ROOT, check=True)
    schema = run("schema", "weather").stdout
    assert json.loads(schema)["name"] == "weather"

    emitted = run("emit", "weather", "--target", "mcp").stdout
    assert json.loads(emitted)["name"] == "weather"
    assert run("check", "weather", "--target", "mcp").returncode == 0

    with tempfile.TemporaryDirectory() as directory:
        output = pathlib.Path(directory) / "weather.json"
        run("emit", "weather", "--target", "mcp", "--out", str(output))
        assert output.read_text() == emitted.rstrip("\n")
        run("check", "weather", "--target", "mcp", "--generated", str(output))
        output.write_text("{}")
        stale = run(
            "check",
            "weather",
            "--target",
            "mcp",
            "--generated",
            str(output),
            expected=1,
        )
        assert json.loads(stale.stderr.splitlines()[0])["code"] == "stale_generated_file"

    malformed = run("emit", "weather", expected=2)
    assert "emit requires" in malformed.stderr
    unsupported = run("emit", "remove", "--target", "openai", expected=1)
    assert json.loads(unsupported.stderr.splitlines()[0])["code"] == "lossy_mapping"

    launcher = subprocess.run(
        [ROOT / "zig-out/bin/zig-tool", "schema", "weather"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    assert json.loads(launcher.stdout)["name"] == "weather"


if __name__ == "__main__":
    main()
