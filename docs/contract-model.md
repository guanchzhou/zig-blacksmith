# Contract model

Each `blacksmith.Tool` binds a function to comptime metadata. The function supplies input, optional host, output, and error-set types; metadata supplies stable names, descriptions, constraints, defaults, examples, declared error mappings, and safety hints.

## Supported types

Model-visible contracts support booleans, integers, floats, byte strings, slices and arrays, structs, enums, tagged unions, optionals, and `void`. Unsupported pointers, resources, untagged unions, recursive shapes, ambiguous metadata paths, duplicate names, and malformed declared-error mappings fail at compile time.

Nested field metadata uses dotted paths such as `options.language`. Field order follows declaration order, producing deterministic schema bytes.

Integers carry their type's range as `minimum` and `maximum`, narrowed by declared bounds and compared as integers. String lengths count Unicode code points. Fixed-size arrays declare their length. Constraints must match the field's kind and bounds must be finite; violations fail at compile time.

## Requiredness and defaults

A field is required unless it is optional, has a Zig struct default, or declares `default_json`. A declared JSON default is validated, omitted from the schema's required set, and inserted after all supplied values pass validation. Explicit JSON `null` is valid only for optional fields.

## Handler shapes

Supported functions have one model input:

```zig
fn handler(input: Input) Output
fn handler(input: Input) ErrorSet!Output
```

They may add one host-only value:

```zig
fn handler(input: Input, host: Host) ErrorSet!Output
```

The caller supplies `Host` through `invokeWithHost`; it never appears in schemas.

## Runtime

The decoder parses to `std.json.Value`, rejecting duplicate object keys, validates recursively against the same types and metadata used by emitters, applies defaults, and constructs the typed input. Unknown fields are rejected. Dispatch is synchronous.

Results are normalized as:

- `{"kind":"success","output":...}`
- `{"kind":"tool_error","code":"...","message":"..."}`
- `{"kind":"validation_error",...}`
- `{"kind":"internal_error","code":"internal_error","message":"tool execution failed"}`

Diagnostics expose categories and JSON paths but never submitted values or undeclared internal errors.

## Ownership

`contractJson`, `emitJson`, `invoke`, and `invokeWithHost` return allocator-owned byte slices. The caller must free them with the same allocator. Parsed input and intermediate values live in a dispatch-local arena and are released on every return path.
