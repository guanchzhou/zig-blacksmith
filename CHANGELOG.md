# Changelog

## 0.1.2 - 2026-10-25

- Validate array elements against their own type instead of the array field's constraints, so `{"rows":[[]]}` is accepted when `rows` has `min_items = 1`. Element diagnostics use paths such as `$.rows[]`.
- Emit `minimum` and `maximum` for every integer schema as exact integers: the integer type's range, narrowed by declared bounds. Generated fixtures for `lookup`, `matrix`, and `scale` change accordingly.
- Compare integer values with declared bounds as integers, so values above 2^53 are no longer rounded before the comparison.
- Count string `min_length` and `max_length` in Unicode code points, matching JSON Schema `minLength` and `maxLength`. Invalid UTF-8 falls back to the byte length.
- Detect duplicate object keys while parsing instead of in a separate scan of the input. They are still reported as `duplicate_key`.
- Accept integral floating-point values such as `5.0` and `1e2` for integer fields within range.
- Emit and enforce the length of fixed-size arrays: `minItems` and `maxItems` for `[N]T`, `minLength` and `maxLength` for `[N]u8`, which must hold exactly `N` bytes.
- Reject non-finite bounds, constraints that do not apply to the field's kind, length constraints on fixed-size arrays, and integer bounds outside the field's type at compile time.
- Add `runtime.decode.checkDefaults` to validate `default_json` values against their fields' types and constraints; the test suite runs it over the example registry.
- `zig-tool` stops searching at a directory containing `.git` or at `$HOME`, requires `build.zig.zon` next to `build.zig`, and prints the chosen project to stderr. A backend killed by a signal exits with 128 plus the signal number.
- CLI diagnostics are serialized with the JSON writer and include every diagnostic field.
- Correction to 0.1.1: constraints have no `exclusive_min` or `exclusive_max`, and a `pattern` constraint is a compile error, so no `pattern` is emitted. Only `minimum` and `maximum` exist for numbers.

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
