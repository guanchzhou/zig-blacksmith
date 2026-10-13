pub const JsonSchemaDialect = "https://json-schema.org/draft/2020-12/schema";
pub const McpProtocolVersion = "2026-07-28";

pub const Constraints = struct {
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    min_items: ?usize = null,
    max_items: ?usize = null,
    pattern: ?[]const u8 = null,
};

pub const FieldMeta = struct {
    name: []const u8,
    description: []const u8 = "",
    constraints: Constraints = .{},
    default_json: ?[]const u8 = null,
    example_json: ?[]const u8 = null,
};

pub const ToolError = struct {
    zig_name: []const u8,
    code: []const u8,
    safe_message: []const u8,
};

pub const Safety = struct {
    read_only: bool = false,
    destructive: bool = false,
    idempotent: bool = false,

    pub fn any(self: Safety) bool {
        return self.read_only or self.destructive or self.idempotent;
    }
};

pub const ToolMeta = struct {
    name: []const u8,
    description: []const u8,
    fields: []const FieldMeta = &.{},
    errors: []const ToolError = &.{},
    safety: Safety = .{},
};

pub const NodeKind = enum {
    boolean,
    integer,
    number,
    string,
    array,
    object,
    enumeration,
    tagged_union,
    optional,
    void,
};

pub fn field(comptime meta: ToolMeta, comptime name: []const u8) ?FieldMeta {
    inline for (meta.fields) |candidate| {
        if (comptime eql(candidate.name, name)) return candidate;
    }
    return null;
}

pub fn declaredError(comptime meta: ToolMeta, name: []const u8) ?ToolError {
    inline for (meta.errors) |candidate| {
        if (eql(candidate.zig_name, name)) return candidate;
    }
    return null;
}

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

test "field metadata lookup" {
    const meta: ToolMeta = .{
        .name = "sum",
        .description = "sum values",
        .fields = &.{.{ .name = "count", .constraints = .{ .minimum = 1 } }},
    };
    const found = field(meta, "count").?;
    try @import("std").testing.expectEqual(@as(?f64, 1), found.constraints.minimum);
}
