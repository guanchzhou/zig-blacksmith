const std = @import("std");
const blacksmith = @import("blacksmith");
const tools = @import("tool_registry");

test "one declaration drives canonical and provider schemas" {
    const canonical = try tools.Weather.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(canonical);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "\"name\":\"weather\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "\"additionalProperties\":false") != null);

    const first = try tools.Weather.emitJson(std.testing.allocator, .mcp);
    defer std.testing.allocator.free(first);
    const second = try tools.Weather.emitJson(std.testing.allocator, .mcp);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"inputSchema\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"outputSchema\"") != null);
}

test "every supported projection is deterministic valid JSON" {
    inline for (tools.Registry.all) |Tool| {
        inline for (@typeInfo(blacksmith.emit.Target).@"enum".field_names) |target_name| {
            const target = @field(blacksmith.emit.Target, target_name);
            if (comptime blacksmith.emit.diagnose(Tool, target) == null) {
                var first: std.Io.Writer.Allocating = .init(std.testing.allocator);
                defer first.deinit();
                try blacksmith.emit.write(&first.writer, Tool, target);
                const first_json = try first.toOwnedSlice();
                defer std.testing.allocator.free(first_json);

                var second: std.Io.Writer.Allocating = .init(std.testing.allocator);
                defer second.deinit();
                try blacksmith.emit.write(&second.writer, Tool, target);
                const second_json = try second.toOwnedSlice();
                defer std.testing.allocator.free(second_json);
                try std.testing.expectEqualStrings(first_json, second_json);

                const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, first_json, .{});
                defer parsed.deinit();
                try std.testing.expect(parsed.value == .object);
            }
        }
    }
}

test "provider projections use current API field names" {
    const openai = try tools.Weather.emitJson(std.testing.allocator, .openai);
    defer std.testing.allocator.free(openai);
    try std.testing.expect(std.mem.indexOf(u8, openai, "\"function\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, openai, "\"output_schema\":") != null);

    const gemini = try tools.Weather.emitJson(std.testing.allocator, .gemini);
    defer std.testing.allocator.free(gemini);
    try std.testing.expect(std.mem.indexOf(u8, gemini, "\"parametersJsonSchema\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gemini, "\"responseJsonSchema\":") != null);
}

test "defaults and optional null are accepted" {
    const defaulted = try tools.Weather.invoke(std.testing.allocator, "{\"location\":\"Helsinki\"}");
    defer std.testing.allocator.free(defaulted);
    try std.testing.expectEqualStrings("{\"kind\":\"success\",\"output\":null}", defaulted);

    const explicit_null = try tools.Weather.invoke(std.testing.allocator, "{\"location\":\"Helsinki\",\"unit\":null}");
    defer std.testing.allocator.free(explicit_null);
    try std.testing.expectEqualStrings("{\"kind\":\"success\",\"output\":null}", explicit_null);
}

test "nested metadata drives schema and runtime validation" {
    const schema = try tools.Weather.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"Optional response language.\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"maxLength\":16") != null);

    const result = try tools.Weather.invoke(
        std.testing.allocator,
        "{\"location\":\"Helsinki\",\"options\":{\"language\":\"this-language-name-is-too-long\"}}",
    );
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"path\":\"$.options.language\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"code\":\"constraint_violation\"") != null);
}

test "metadata mutation changes schema and runtime together" {
    const local = struct {
        fn bounded(_: struct { count: i32 }) void {}
    }.bounded;
    const Mutated = blacksmith.Tool(local, .{
        .name = "mutated",
        .description = "Mutation fixture.",
        .fields = &.{.{ .name = "count", .constraints = .{ .minimum = 5 } }},
    });
    const schema = try Mutated.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"minimum\":5") != null);

    const rejected = try Mutated.invoke(std.testing.allocator, "{\"count\":4}");
    defer std.testing.allocator.free(rejected);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "\"code\":\"constraint_violation\"") != null);
    const accepted = try Mutated.invoke(std.testing.allocator, "{\"count\":5}");
    defer std.testing.allocator.free(accepted);
    try std.testing.expectEqualStrings("{\"kind\":\"success\",\"output\":null}", accepted);
}

test "validation rejects unknown duplicate wrong and missing fields without values" {
    const cases = [_][]const u8{
        "{\"value\":2,\"extra\":\"SECRET\"}",
        "{\"value\":2,\"value\":3}",
        "{\"value\":\"SECRET\"}",
        "{}",
        "{\"value\":1000}",
    };
    for (cases) |input| {
        const result = try tools.Scale.invoke(std.testing.allocator, input);
        defer std.testing.allocator.free(result);
        try std.testing.expect(std.mem.startsWith(u8, result, "{\"kind\":\"validation_error\""));
        try std.testing.expect(std.mem.indexOf(u8, result, "SECRET") == null);
    }
}

test "declared and undeclared errors are normalized" {
    const declared = try tools.Guarded.invoke(std.testing.allocator, "{\"allowed\":false}");
    defer std.testing.allocator.free(declared);
    try std.testing.expectEqualStrings(
        "{\"kind\":\"tool_error\",\"code\":\"denied\",\"message\":\"operation denied\"}",
        declared,
    );

    const local = struct {
        fn fail(_: struct {}) error{Unexpected}!void {
            return error.Unexpected;
        }
    }.fail;
    const Undeclared = blacksmith.Tool(local, .{ .name = "undeclared", .description = "Return an undeclared error." });
    const hidden = try Undeclared.invoke(std.testing.allocator, "{}");
    defer std.testing.allocator.free(hidden);
    try std.testing.expectEqualStrings(
        "{\"kind\":\"internal_error\",\"code\":\"internal_error\",\"message\":\"tool execution failed\"}",
        hidden,
    );
}

test "host injection is not model visible" {
    const schema = try tools.Audit.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "request_id") == null);
    const result = try tools.Audit.invokeWithHost(
        std.testing.allocator,
        "{\"message\":\"hello\"}",
        .{ .request_id = "req-1" },
    );
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("{\"kind\":\"success\",\"output\":null}", result);
}

test "lossy target mappings are explicit" {
    try std.testing.expectEqual(
        blacksmith.diagnostic.Code.lossy_mapping,
        blacksmith.emit.anthropic.diagnose(tools.Echo).?.code,
    );
    try std.testing.expectEqual(
        blacksmith.diagnostic.Code.lossy_mapping,
        blacksmith.emit.gemini.diagnose(tools.Lookup).?.code,
    );
    try std.testing.expectEqual(
        blacksmith.diagnostic.Code.lossy_mapping,
        blacksmith.emit.openai.diagnose(tools.Remove).?.code,
    );
}

test "MCP refuses protocol mismatch" {
    try std.testing.expect(blacksmith.emit.mcp.negotiate("2026-07-28") == null);
    try std.testing.expectEqual(
        blacksmith.diagnostic.Code.protocol_mismatch,
        blacksmith.emit.mcp.negotiate("2025-11-25").?.code,
    );
}

test "nested struct field with default_json is optional on wire and populated at runtime" {
    const Filter = struct {
        limit: u32,
    };
    const Query = struct {
        filter: Filter,
    };
    const handler = struct {
        fn run(q: Query) u32 {
            return q.filter.limit;
        }
    }.run;
    const Paginated = blacksmith.Tool(handler, .{
        .name = "paginated",
        .description = "Nested default_json fixture.",
        .fields = &.{.{ .name = "filter.limit", .default_json = "25" }},
    });

    const out = try Paginated.invoke(std.testing.allocator, "{\"filter\":{}}");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("{\"kind\":\"success\",\"output\":25}", out);
}

fn expectInvoke(comptime Tool: type, input: []const u8, needle: []const u8) !void {
    const result = try Tool.invoke(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    if (std.mem.indexOf(u8, result, needle) == null) {
        std.debug.print("expected {s} in {s}\n", .{ needle, result });
        return error.TestUnexpectedResult;
    }
}

test "array elements are not checked against the array field's constraints" {
    try expectInvoke(tools.Matrix, "{\"rows\":[[]]}", "\"kind\":\"success\"");
    try expectInvoke(tools.Matrix, "{\"rows\":[[1,2],[3]]}", "\"kind\":\"success\"");
    try expectInvoke(tools.Matrix, "{\"rows\":[]}", "\"path\":\"$.rows\"");
    try expectInvoke(tools.Matrix, "{\"rows\":[[2147483648]]}", "\"path\":\"$.rows[][]\"");
}

test "duplicate keys are reported as duplicate_key" {
    try expectInvoke(tools.Scale, "{\"value\":2,\"value\":3}", "\"code\":\"duplicate_key\"");
    try expectInvoke(tools.Weather, "{\"location\":\"x\",\"options\":{\"language\":\"a\",\"language\":\"b\"}}", "\"code\":\"duplicate_key\"");
    try expectInvoke(tools.Scale, "{\"value\":2", "\"code\":\"invalid_json\"");
}

test "integer schemas carry the type range" {
    const lookup = try tools.Lookup.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(lookup);
    try std.testing.expect(std.mem.indexOf(u8, lookup, "{\"type\":\"integer\",\"minimum\":0,\"maximum\":18446744073709551615}") != null);

    const scale = try tools.Scale.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(scale);
    try std.testing.expect(std.mem.indexOf(u8, scale, "{\"type\":\"integer\",\"minimum\":-100,\"maximum\":100,") != null);
    try std.testing.expect(std.mem.indexOf(u8, scale, "{\"type\":\"integer\",\"minimum\":-2147483648,\"maximum\":2147483647}") != null);
}

test "integer bounds compare without floating point rounding" {
    const local = struct {
        fn run(_: struct { id: i64, small: u8 }) void {}
    }.run;
    const Exact = blacksmith.Tool(local, .{
        .name = "exact",
        .description = "Exact integer bounds.",
        .fields = &.{
            .{ .name = "id", .constraints = .{ .maximum = 9007199254740992 } },
            .{ .name = "small", .constraints = .{ .minimum = 1.5, .maximum = 1000 } },
        },
    });
    const schema = try Exact.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"minimum\":-9223372036854775808,\"maximum\":9007199254740992") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"minimum\":2,\"maximum\":255") != null);

    try expectInvoke(Exact, "{\"id\":9007199254740992,\"small\":2}", "\"kind\":\"success\"");
    try expectInvoke(Exact, "{\"id\":9007199254740993,\"small\":2}", "\"expected\":\"numeric bounds\"");
    try expectInvoke(Exact, "{\"id\":1,\"small\":1}", "\"expected\":\"numeric bounds\"");
    try expectInvoke(Exact, "{\"id\":1,\"small\":256}", "\"expected\":\"integer type range\"");
    try expectInvoke(Exact, "{\"id\":9223372036854775808,\"small\":2}", "\"expected\":\"integer type range\"");
    try expectInvoke(Exact, "{\"id\":9.223372036854775807e18,\"small\":2}", "\"expected\":\"integer type range\"");
}

test "integer fields accept integral floats" {
    try expectInvoke(tools.Scale, "{\"value\":5.0}", "{\"kind\":\"success\",\"output\":10}");
    try expectInvoke(tools.Scale, "{\"value\":1e2}", "{\"kind\":\"success\",\"output\":200}");
    try expectInvoke(tools.Scale, "{\"value\":-1E1}", "{\"kind\":\"success\",\"output\":-20}");
    try expectInvoke(tools.Scale, "{\"value\":1.01e2}", "\"expected\":\"numeric bounds\"");
    try expectInvoke(tools.Scale, "{\"value\":5.5}", "\"code\":\"wrong_type\"");
    try expectInvoke(tools.Scale, "{\"value\":1e400}", "\"expected\":\"integer type range\"");
}

fn repeated(comptime text: []const u8, comptime count: usize) []const u8 {
    comptime var out: []const u8 = "";
    inline for (0..count) |_| out = out ++ text;
    return out;
}

test "string lengths count code points" {
    const fits = comptime "{\"text\":\"" ++ repeated("\u{e9}", 256) ++ "\"}";
    try expectInvoke(tools.Echo, fits, "\"kind\":\"success\"");
    const too_long = comptime "{\"text\":\"" ++ repeated("\u{e9}", 257) ++ "\"}";
    try expectInvoke(tools.Echo, too_long, "\"expected\":\"maximum string length\"");
}

test "fixed-length arrays declare and enforce their length" {
    const local = struct {
        fn run(_: struct { point: [3]i32, code: [2]u8 }) void {}
    }.run;
    const Fixed = blacksmith.Tool(local, .{ .name = "fixed", .description = "Fixed-length arrays." });
    const schema = try Fixed.contractJson(std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"minItems\":3,\"maxItems\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "{\"type\":\"string\",\"minLength\":2,\"maxLength\":2}") != null);

    try expectInvoke(Fixed, "{\"point\":[1,2,3],\"code\":\"fi\"}", "\"kind\":\"success\"");
    try expectInvoke(Fixed, "{\"point\":[1,2],\"code\":\"fi\"}", "\"expected\":\"fixed array length\"");
    try expectInvoke(Fixed, "{\"point\":[1,2,3],\"code\":\"fin\"}", "\"expected\":\"fixed string length\"");
}

test "registry defaults satisfy their own constraints" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    inline for (tools.Registry.all) |Tool| {
        if (try blacksmith.runtime.decode.checkDefaults(Tool.Input, Tool.meta, arena_state.allocator())) |failure| {
            std.debug.print("{s}: default for {s} fails: {s}\n", .{ Tool.meta.name, failure.path, failure.message });
            return error.TestUnexpectedResult;
        }
    }

    const local = struct {
        fn run(_: struct { count: u8, name: []const u8 }) void {}
    }.run;
    const meta: blacksmith.contract.ToolMeta = .{
        .name = "bad_defaults",
        .description = "Defaults that violate constraints.",
        .fields = &.{
            .{ .name = "count", .constraints = .{ .maximum = 10 }, .default_json = "11" },
            .{ .name = "name", .constraints = .{ .max_length = 2 }, .default_json = "\"abc\"" },
        },
    };
    _ = blacksmith.Tool(local, meta);
    const failure = (try blacksmith.runtime.decode.checkDefaults(struct { count: u8, name: []const u8 }, meta, arena_state.allocator())).?;
    try std.testing.expectEqualStrings("$.count", failure.path);
    try std.testing.expectEqual(blacksmith.diagnostic.Code.constraint_violation, failure.code);
}
