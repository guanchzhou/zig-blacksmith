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
