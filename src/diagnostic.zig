const std = @import("std");

pub const Stage = enum {
    declaration,
    derivation,
    emission,
    validation,
    dispatch,
    protocol,
};

pub const Target = enum {
    canonical,
    json_schema,
    openai,
    anthropic,
    gemini,
    mcp,
    runtime,
};

pub const Code = enum {
    invalid_declaration,
    unsupported_type,
    unsupported_feature,
    lossy_mapping,
    invalid_json,
    duplicate_key,
    unknown_field,
    missing_field,
    wrong_type,
    constraint_violation,
    invalid_enum,
    invalid_null,
    undeclared_tool_error,
    internal_error,
    protocol_mismatch,
    stale_generated_file,
};

pub const Diagnostic = struct {
    stage: Stage,
    code: Code,
    target: Target,
    path: []const u8 = "$",
    feature: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    actual_category: ?[]const u8 = null,
    message: []const u8,

    pub fn writeJson(self: Diagnostic, writer: *std.Io.Writer) !void {
        try std.json.Stringify.value(self, .{}, writer);
    }
};

pub fn safe(
    stage: Stage,
    code: Code,
    target: Target,
    path: []const u8,
    expected: ?[]const u8,
    actual_category: ?[]const u8,
    message: []const u8,
) Diagnostic {
    return .{
        .stage = stage,
        .code = code,
        .target = target,
        .path = path,
        .expected = expected,
        .actual_category = actual_category,
        .message = message,
    };
}

test "diagnostics serialize without submitted values" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try safe(.validation, .wrong_type, .runtime, "$.count", "integer", "string", "invalid argument type").writeJson(&out.writer);
    try std.testing.expectEqualStrings(
        "{\"stage\":\"validation\",\"code\":\"wrong_type\",\"target\":\"runtime\",\"path\":\"$.count\",\"feature\":null,\"expected\":\"integer\",\"actual_category\":\"string\",\"message\":\"invalid argument type\"}",
        out.written(),
    );
}
