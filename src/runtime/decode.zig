const std = @import("std");
const contract = @import("../contract.zig");
const derive = @import("../derive.zig");
const diagnostic = @import("../diagnostic.zig");

pub const Decoded = struct {
    value: std.json.Value,
};

pub fn decode(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    arena: std.mem.Allocator,
    text: []const u8,
) !union(enum) {
    ok: T,
    invalid: diagnostic.Diagnostic,
} {
    var parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.DuplicateField => return .{ .invalid = diagnostic.safe(
            .validation,
            .duplicate_key,
            .runtime,
            "$",
            "unique object keys",
            "duplicate_key",
            "duplicate object key",
        ) },
        else => return .{ .invalid = diagnostic.safe(
            .validation,
            .invalid_json,
            .runtime,
            "$",
            "valid JSON",
            "malformed_json",
            "invalid JSON input",
        ) },
    };

    if (validateValue(T, meta, parsed, "$")) |failure| return .{ .invalid = failure };
    try applyDefaults(T, meta, arena, &parsed, "");

    const typed = std.json.parseFromValueLeaky(T, arena, parsed, .{}) catch
        return .{ .invalid = diagnostic.safe(
            .validation,
            .wrong_type,
            .runtime,
            "$",
            "declared input contract",
            "conversion_failure",
            "input does not match the declared contract",
        ) };
    return .{ .ok = typed };
}

fn validateValue(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
) ?diagnostic.Diagnostic {
    switch (@typeInfo(T)) {
        .bool => if (value != .bool) return wrong(path, "boolean", category(value)),
        .int => return validateInteger(T, meta, value, path),
        .float, .comptime_float => {
            const number = switch (value) {
                .float => |v| v,
                .integer => |v| @as(f64, @floatFromInt(v)),
                .number_string => |v| std.fmt.parseFloat(f64, v) catch return wrong(path, "number", "number"),
                else => return wrong(path, "number", category(value)),
            };
            if (fieldConstraints(meta, path)) |constraints| if (numericViolation(constraints, number))
                return constraintFailure(path, "numeric bounds");
        },
        .void => if (value != .null) return wrong(path, "null", category(value)),
        .optional => |optional| {
            if (value == .null) return null;
            return validateValue(optional.child, meta, value, path);
        },
        .pointer => |pointer| {
            if (pointer.child == u8) return validateString(meta, value, path, null);
            return validateArray(pointer.child, meta, value, path, null);
        },
        .array => |array| {
            if (array.child == u8) return validateString(meta, value, path, array.len);
            return validateArray(array.child, meta, value, path, array.len);
        },
        .@"enum" => |enumeration| {
            const text = switch (value) {
                .string => |v| v,
                else => return wrong(path, "enum string", category(value)),
            };
            inline for (enumeration.field_names) |name| if (std.mem.eql(u8, text, name)) return null;
            return .{
                .stage = .validation,
                .code = .invalid_enum,
                .target = .runtime,
                .path = path,
                .expected = "declared enum member",
                .actual_category = "string",
                .message = "invalid enum member",
            };
        },
        .@"struct" => |object_info| {
            const object = switch (value) {
                .object => |v| v,
                else => return wrong(path, "object", category(value)),
            };
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                var known = false;
                inline for (object_info.field_names) |field_name| {
                    if (std.mem.eql(u8, entry.key_ptr.*, field_name)) known = true;
                }
                if (!known) return .{
                    .stage = .validation,
                    .code = .unknown_field,
                    .target = .runtime,
                    .path = path,
                    .expected = "declared field",
                    .actual_category = "unknown_field",
                    .message = "unknown input field",
                };
            }
            inline for (object_info.field_names, object_info.field_types, 0..) |field_name, field_type, i| {
                const child_path = path ++ "." ++ field_name;
                if (object.get(field_name)) |child| {
                    if (validateValue(field_type, meta, child, child_path)) |failure| return failure;
                } else {
                    const fm = derive.fieldMeta(meta, child_path[2..]);
                    if (!derive.isOptional(field_type) and !derive.hasDefault(T, i) and fm.default_json == null)
                        return .{
                            .stage = .validation,
                            .code = .missing_field,
                            .target = .runtime,
                            .path = child_path,
                            .expected = "required field",
                            .actual_category = "missing",
                            .message = "required field is missing",
                        };
                }
            }
        },
        .@"union" => |union_info| {
            const object = switch (value) {
                .object => |v| v,
                else => return wrong(path, "tagged union object", category(value)),
            };
            if (object.count() != 1) return wrong(path, "single tagged union member", "object");
            inline for (union_info.field_names, union_info.field_types) |field_name, field_type| {
                if (object.get(field_name)) |child| return validateValue(field_type, meta, child, path ++ "." ++ field_name);
            }
            return wrong(path, "declared union tag", "unknown_tag");
        },
        else => unreachable,
    }
    return null;
}

fn validateInteger(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
) ?diagnostic.Diagnostic {
    const W = derive.Wide(T);
    const number: W = switch (value) {
        .integer => |v| v,
        .float => |v| blk: {
            if (@floor(v) != v) return wrong(path, "integer", "number");
            break :blk floatInteger(W, v) orelse return constraintFailure(path, "integer type range");
        },
        .number_string => |v| std.fmt.parseInt(W, v, 10) catch return constraintFailure(path, "integer type range"),
        else => return wrong(path, "integer", category(value)),
    };
    if (number < std.math.minInt(T) or number > std.math.maxInt(T))
        return constraintFailure(path, "integer type range");
    if (comptime fieldConstraints(meta, path)) |constraints| {
        const bounds = comptime derive.integerBounds(T, constraints);
        if (number < bounds.min or number > bounds.max) return constraintFailure(path, "numeric bounds");
    }
    return null;
}

fn floatInteger(comptime W: type, value: f64) ?W {
    const limit = comptime std.math.ldexp(@as(f64, 1), @typeInfo(W).int.bits - 1);
    if (value < -limit or value >= limit) return null;
    return @intFromFloat(value);
}

fn validateString(
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
    comptime fixed_len: ?usize,
) ?diagnostic.Diagnostic {
    const text = switch (value) {
        .string => |v| v,
        else => return wrong(path, "string", category(value)),
    };
    if (fixed_len) |len| if (text.len != len) return constraintFailure(path, "fixed string length");
    if (fieldConstraints(meta, path)) |constraints| {
        const count = std.unicode.utf8CountCodepoints(text) catch text.len;
        if (constraints.min_length) |minimum| if (count < minimum) return constraintFailure(path, "minimum string length");
        if (constraints.max_length) |maximum| if (count > maximum) return constraintFailure(path, "maximum string length");
    }
    return null;
}

fn validateArray(
    comptime Child: type,
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
    comptime fixed_len: ?usize,
) ?diagnostic.Diagnostic {
    const array = switch (value) {
        .array => |v| v,
        else => return wrong(path, "array", category(value)),
    };
    if (fixed_len) |len| if (array.items.len != len) return constraintFailure(path, "fixed array length");
    if (fieldConstraints(meta, path)) |constraints| {
        if (constraints.min_items) |minimum| if (array.items.len < minimum) return constraintFailure(path, "minimum array length");
        if (constraints.max_items) |maximum| if (array.items.len > maximum) return constraintFailure(path, "maximum array length");
    }
    for (array.items) |child| if (validateValue(Child, meta, child, path ++ "[]")) |failure| return failure;
    return null;
}

fn applyDefaults(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    arena: std.mem.Allocator,
    value: *std.json.Value,
    comptime path: []const u8,
) !void {
    const Effective = switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
    const info = @typeInfo(Effective);
    if (info != .@"struct" or value.* != .object) return;
    inline for (info.@"struct".field_names, info.@"struct".field_types) |field_name, field_type| {
        const child_path = if (path.len == 0) field_name else path ++ "." ++ field_name;
        const fm = derive.fieldMeta(meta, child_path);
        if (!value.object.contains(field_name)) {
            if (fm.default_json) |raw| {
                const default = try std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{});
                try value.object.put(arena, field_name, default);
            }
        }
        if (value.object.getPtr(field_name)) |child| try applyDefaults(field_type, meta, arena, child, child_path);
    }
}

pub fn checkDefaults(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    arena: std.mem.Allocator,
) !?diagnostic.Diagnostic {
    inline for (meta.fields) |field_meta| {
        if (field_meta.default_json) |raw| {
            const path = "$." ++ field_meta.name;
            const value = std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{}) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return diagnostic.safe(.validation, .invalid_json, .runtime, path, "valid JSON", "malformed_json", "invalid JSON default"),
            };
            if (validateValue(derive.FieldType(T, field_meta.name), meta, value, path)) |failure| return failure;
        }
    }
    return null;
}

fn fieldConstraints(comptime meta: contract.ToolMeta, comptime path: []const u8) ?contract.Constraints {
    if (!std.mem.startsWith(u8, path, "$.")) return null;
    return (contract.field(meta, path[2..]) orelse return null).constraints;
}

fn numericViolation(c: contract.Constraints, value: f64) bool {
    if (c.minimum) |minimum| if (value < minimum) return true;
    if (c.maximum) |maximum| if (value > maximum) return true;
    return false;
}

fn wrong(comptime path: []const u8, expected: []const u8, actual: []const u8) diagnostic.Diagnostic {
    return diagnostic.safe(.validation, .wrong_type, .runtime, path, expected, actual, "invalid argument type");
}

fn constraintFailure(comptime path: []const u8, expected: []const u8) diagnostic.Diagnostic {
    return diagnostic.safe(.validation, .constraint_violation, .runtime, path, expected, "out_of_range", "argument violates a declared constraint");
}

fn category(value: std.json.Value) []const u8 {
    return switch (value) {
        .null => "null",
        .bool => "boolean",
        .integer, .float, .number_string => "number",
        .string => "string",
        .array => "array",
        .object => "object",
    };
}

test "std.json rejects duplicate keys when parsing a dynamic value" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(error.DuplicateField, std.json.parseFromSliceLeaky(std.json.Value, arena, "{\"a\":1,\"a\":2}", .{}));
    try std.testing.expectError(error.DuplicateField, std.json.parseFromSliceLeaky(std.json.Value, arena, "[{\"b\":{\"a\":1,\"\\u0061\":2}}]", .{}));
    _ = try std.json.parseFromSliceLeaky(std.json.Value, arena, "{\"a\":{\"a\":1},\"b\":{\"a\":2}}", .{});
}
