#!/usr/bin/env python3
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_AUTHOR = "Andrey Maltsev"
EXPECTED_EMAIL = "maltsev.andrey@gmail.com"
FORBIDDEN_TRAILERS = ("Co-" + "authored-by:", "Generated-" + "by:")


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)


def main() -> None:
    # CI runners have no user identity configured; only check it where one is set.
    configured = git("config", "user.name")
    if configured.returncode == 0:
        assert configured.stdout.strip() == EXPECTED_AUTHOR

    history = git("log", "--format=%an%n%cn")
    if history.returncode == 0:
        authors = {line for line in history.stdout.splitlines() if line}
        assert authors <= {EXPECTED_AUTHOR}, authors
        emails = {line for line in git("log", "--format=%ae%n%ce").stdout.splitlines() if line}
        assert emails <= {EXPECTED_EMAIL}, emails
        messages = git("log", "--format=%B").stdout
        for trailer in FORBIDDEN_TRAILERS:
            assert trailer not in messages, f"commit message contains {trailer}"
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
