#!/usr/bin/env python3
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_AUTHOR = "Andrey Maltsev"
FORBIDDEN_TRAILERS = ("Co-" + "authored-by:", "Generated-" + "by:")


def main() -> None:
    configured = subprocess.run(
        ["git", "config", "user.name"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    assert configured == EXPECTED_AUTHOR

    history = subprocess.run(
        ["git", "log", "--format=%an%n%cn"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if history.returncode == 0:
        authors = {line for line in history.stdout.splitlines() if line}
        assert authors <= {EXPECTED_AUTHOR}
    else:
        assert "does not have any commits yet" in history.stderr

    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts or ".zig-cache" in path.parts or "zig-out" in path.parts:
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        for trailer in FORBIDDEN_TRAILERS:
            assert trailer not in text, f"{path.relative_to(ROOT)} contains {trailer}"

    assert EXPECTED_AUTHOR in (ROOT / "LICENSE").read_text()
    assert EXPECTED_AUTHOR in (ROOT / "README.md").read_text()


if __name__ == "__main__":
    main()
