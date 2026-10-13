# Provider compatibility

Provider definitions are generated only when every declared semantic is representable. A rejected projection returns a structured `lossy_mapping` diagnostic naming the target and feature.

## Canonical JSON Schema

The canonical contract uses JSON Schema draft 2020-12 and preserves input, output, declared errors, constraints, defaults, examples, and safety metadata.

## OpenAI

The emitter targets the current Responses API function-tool shape: top-level `type`, `name`, `description`, `strict`, `parameters`, and `output_schema`. It emits `strict: false` because blacksmith preserves optional/default semantics that do not satisfy OpenAI's stricter required-field subset.

Unsupported mappings:

- MCP safety annotations
- declared tool-error contracts

## Anthropic

The emitter produces `name`, `description`, `strict`, and `input_schema`.

Unsupported mappings:

- non-`void` output schemas
- safety annotations
- declared tool-error contracts

## Gemini

The emitter uses `parametersJsonSchema` and `responseJsonSchema`, avoiding the narrower OpenAPI-style `parameters` and `response` fields.

Unsupported mappings:

- tagged unions in input or output
- safety annotations
- declared tool-error contracts

## MCP

The emitter produces `inputSchema`, `outputSchema`, and read-only, destructive, and idempotent annotations. Protocol negotiation is pinned to `2026-07-28`; mismatches are refused.

Declared tool-error contracts are not expressible in MCP tool definitions and are rejected.

Live `zig-mcp-sdk` integration is not claimed in 0.1. Version 0.5.0 targets Zig 0.16 and exposes already-parsed `std.json.Value` arguments, so it cannot preserve Zig 0.17 compatibility and the single-parser runtime boundary. MCP definition generation remains supported.

## Updating fixtures

Upstream samples and their source, retrieval date, license, and SHA-256 are pinned under `test/fixtures/upstream`. Generated golden files change only through:

```sh
zig build blacksmith -- fixtures generate all --ack-version 2026-07-28
python3 test/validate_fixtures.py
```
