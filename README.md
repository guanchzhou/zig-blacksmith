# zig-blacksmith

`zig-blacksmith` derives strict AI-tool contracts from typed Zig functions. One declaration drives validation, synchronous dispatch, canonical JSON Schema, OpenAI, Anthropic, Gemini, and MCP definitions.

## Requirements

- Zig 0.17.0
- No runtime dependencies

## Declaration

```zig
const blacksmith = @import("blacksmith");

const WeatherInput = struct {
    location: []const u8,
    unit: ?enum { celsius, fahrenheit } = null,
};

fn weather(input: WeatherInput) void {
    _ = input;
}

pub const Weather = blacksmith.Tool(weather, .{
    .name = "weather",
    .description = "Read current weather.",
    .fields = &.{
        .{ .name = "location", .description = "City and country.", .constraints = .{ .min_length = 1 } },
        .{ .name = "unit", .default_json = "\"celsius\"" },
    },
});

pub const Registry = blacksmith.Registry(.{Weather});
```

Handlers accept one model-visible struct and may accept one additional host-injected value. Calls are synchronous in 0.1.

## CLI

The CLI backend is compiled against a project's registry because Zig reflection happens at compile time. Register `src/cli/backend.zig` with imports named `blacksmith`, `tool_registry`, and `build_options`, or use `build_integration.addToolCommands` when the helper source is available to the consumer build.

This repository's example registry supports:

```sh
zig build blacksmith -- schema weather
zig build blacksmith -- emit weather --target mcp
zig build blacksmith -- emit weather --target openai --out weather.json
zig build blacksmith -- check weather --target mcp --generated weather.json
zig build blacksmith -- fixtures generate all --ack-version 2026-07-28
```

`zig build install` installs the generic `zig-tool` launcher and the example project-bound backend. The launcher finds the nearest `build.zig` and delegates to its `blacksmith` build step.

## Runtime guarantees

- Duplicate keys, unknown fields, malformed JSON, wrong types, missing values, and constraint violations fail before dispatch.
- Defaults apply after supplied values validate.
- Explicit `null` is accepted only for optional fields.
- Host values are never model-visible.
- Declared errors receive stable safe messages; undeclared errors become generic internal failures.
- Provider generation fails with `lossy_mapping` rather than silently dropping semantics.

## Development

```sh
zig fmt --check build.zig src test examples spikes bench
zig build test
zig build docs
zig build fuzz-smoke
python3 test/validate_fixtures.py
python3 test/test_cli.py
zig build bench
python3 bench/measure_build.py
```

See [contract model](docs/contract-model.md), [provider compatibility](docs/provider-compatibility.md), and the [incompatibility ledger](docs/incompatibility-ledger.md).

## License

MIT. Copyright Andrey Maltsev.
