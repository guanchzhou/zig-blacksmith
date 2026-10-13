#!/usr/bin/env python3
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "test/fixtures/upstream"
GENERATED = ROOT / "test/fixtures/generated"

PINNED = {
    "anthropic-tool.json": "ea29307adaf69f64c147e88ad43308c6d47cf55821b0502016bcbee511394bdc",
    "gemini-function-declaration.json": "37eb4b6d40eea585ddfb43dbca3353ca9dcdb722d12dd47c7052d91cac6b989b",
    "mcp-tool.json": "63f51e0dab30b831d2b9741819c87b8ef91b70692e83bac458d94ce4ac4bfab3",
    "openai-function-tool.json": "dc1eb1a0bf740cf67d45a90af20f928129b2c5d994ec9c39bd49432aa5161239",
}


def schema(value: object) -> None:
    assert isinstance(value, dict)
    if "properties" in value:
        assert value.get("type") == "object"
        assert value.get("additionalProperties") is False
        assert isinstance(value.get("required"), list)
        for child in value["properties"].values():
            schema(child)
    if "items" in value:
        schema(value["items"])
    for keyword in ("anyOf", "oneOf"):
        for child in value.get(keyword, []):
            schema(child)


def validate_generated(path: pathlib.Path) -> None:
    value = json.loads(path.read_text())
    assert isinstance(value, dict)
    suffix = path.stem.rsplit(".", 1)[-1]
    if suffix == "json_schema":
        schema(value)
    elif suffix == "openai":
        assert value["type"] == "function"
        assert "function" not in value
        schema(value["parameters"])
        schema(value["output_schema"])
    elif suffix == "anthropic":
        assert value["strict"] is True
        schema(value["input_schema"])
    elif suffix == "gemini":
        schema(value["parametersJsonSchema"])
        schema(value["responseJsonSchema"])
    elif suffix == "mcp":
        schema(value["inputSchema"])
        schema(value["outputSchema"])
        assert isinstance(value["annotations"], dict)
    else:
        raise AssertionError(f"unknown fixture target: {path.name}")


def main() -> None:
    metadata = (UPSTREAM / "README.md").read_text()
    for name, expected in PINNED.items():
        content = (UPSTREAM / name).read_bytes()
        assert hashlib.sha256(content).hexdigest() == expected
        assert expected in metadata
        json.loads(content)

    fixtures = sorted(GENERATED.glob("*.json"))
    assert fixtures
    for fixture in fixtures:
        validate_generated(fixture)


if __name__ == "__main__":
    main()
