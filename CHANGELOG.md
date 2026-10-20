# Changelog

## 0.1.1 - 2026-10-20

- Preserve full 64-bit integer precision when checking `min`, `max`, `exclusive_min`, and `exclusive_max` constraints in `runtime.decode`.
- Resolve nested struct field metadata (`child_path[2..]`) when applying `default_json` during validation.
- Emit string `pattern` constraints in `targets.jsonschema`.

## 0.1.0

- Define typed tool declarations and project registries.
- Derive canonical contracts from Zig 0.17 types and metadata.
- Emit deterministic JSON Schema, OpenAI, Anthropic, Gemini, and MCP projections.
- Validate and dispatch synchronous calls with safe structured diagnostics.
- Provide the project-bound `zig-tool` command workflow.
