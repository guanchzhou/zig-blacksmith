# Provider incompatibility ledger

Verified on 2026-10-11 against current provider documentation and
`PaytonWebber/zig-mcp-sdk` 0.5.0.

## Contract corpus

The spike covers constrained integers, nested structs, defaults, optionals,
enums, tagged-union outputs, host injection, declared errors, empty
input/output, bounded strings, nested arrays, safety hints, and bounded
floating-point values. `spikes/contracts.zig` asserts that all ten declarations
remain in the corpus.

## Target results

| Contract feature | JSON Schema 2020-12 | OpenAI | Anthropic | Gemini | MCP 2026-07-28 |
| --- | --- | --- | --- | --- | --- |
| Required fields and closed objects | Preserved | Preserved with strict mode | Preserved with strict mode | Preserved | Preserved |
| Defaults and optional null | Preserved | Preserved | Preserved | Preserved | Preserved |
| Bounds, enums, arrays, nested structs | Preserved | Preserved within strict subset | Preserved | Preserved within supported subset | Preserved |
| Tagged unions | Preserved as `oneOf` | Preserved as `oneOf` | Input schema only | Rejected by emitter | Preserved |
| Output schema | Preserved | Preserved by `output_schema` | Rejected by emitter | Preserved by `response` | Preserved by `outputSchema` |
| Read-only, destructive, idempotent hints | Canonical contract | Rejected by emitter | Rejected by emitter | Rejected by emitter | Preserved as annotations |
| Host-injected parameter | Omitted from model schema | Omitted | Omitted | Omitted | Omitted |
| Declared tool errors | Canonical runtime envelope | Runtime envelope | Runtime envelope | Runtime envelope | Runtime envelope |

The compiler rejects every unsupported cell with `lossy_mapping`; no emitter
silently removes a declared feature.

## zig-mcp-sdk compatibility gate

Live SDK integration is excluded from 0.1 for two independently verified
reasons:

1. Version 0.5.0 targets Zig 0.16 and does not build on Zig 0.17.0. Its build
   fails because package paths require `Build.LazyPath` and `Build.args` no
   longer exists.
2. `CallToolParams.arguments` is already a parsed `std.json.Value`, and
   `ToolPack.callTool` invokes `parseArgs` internally. The SDK does not expose
   the original argument JSON bytes, so integrating blacksmith would require a
   second serialization/parsing pass.

MCP definition emission remains enabled. A live adapter can be added only
after the SDK supports Zig 0.17 and exposes raw argument JSON before typed
parsing. Until then, blacksmith does not claim live SDK integration.
