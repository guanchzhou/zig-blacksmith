const std = @import("std");
const contract = @import("../contract.zig");
const derive = @import("../derive.zig");
const diagnostic = @import("../diagnostic.zig");

pub const Decoded = struct {
    value: std.json.Value,
};

const Frame = struct {
    keys: std.StringHashMapUnmanaged(void) = .empty,
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
    if (try duplicateKey(arena, text)) |key| {
        _ = key;
        return .{ .invalid = diagnostic.safe(
            .validation,
            .duplicate_key,
            .runtime,
            "$",
            "unique object keys",
            "duplicate_key",
            "duplicate object key",
        ) };
    }

    var parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch
        return .{ .invalid = diagnostic.safe(
            .validation,
            .invalid_json,
            .runtime,
            "$",
            "valid JSON",
            "malformed_json",
            "invalid JSON input",
        ) };

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

fn duplicateKey(arena: std.mem.Allocator, text: []const u8) !?[]const u8 {
    var scanner = std.json.Scanner.initCompleteInput(arena, text);
    defer scanner.deinit();
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(arena);

    while (true) {
        const token = scanner.nextAlloc(arena, .alloc_if_needed) catch return null;
        switch (token) {
            .object_begin => try frames.append(arena, .{}),
            .object_end => {
                if (frames.items.len != 0) {
                    var frame = frames.pop().?;
                    frame.keys.deinit(arena);
                }
            },
            .string, .allocated_string => |key| {
                if (scanner.string_is_object_key and frames.items.len != 0) {
                    const owned = try arena.dupe(u8, key);
                    const result = try frames.items[frames.items.len - 1].keys.getOrPut(arena, owned);
                    if (result.found_existing) return key;
                }
            },
            .end_of_document => return null,
            else => {},
        }
    }
}

fn validateValue(
    comptime T: type,
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
) ?diagnostic.Diagnostic {
    switch (@typeInfo(T)) {
        .bool => if (value != .bool) return wrong(path, "boolean", category(value)),
        .int => {
            const number = switch (value) {
                .integer => |v| blk: {
                    if (v < std.math.minInt(T) or v > std.math.maxInt(T))
                        return constraintFailure(path, "integer type range");
                    break :blk @as(f64, @floatFromInt(v));
                },
                .number_string => |v| blk: {
                    if (std.fmt.parseInt(T, v, 10)) |iv| {
                        break :blk @as(f64, @floatFromInt(iv));
                    } else |_| {
                        const fv = std.fmt.parseFloat(f64, v) catch return wrong(path, "integer", "number");
                        if (@floor(fv) != fv) return wrong(path, "integer", "number");
                        return constraintFailure(path, "integer type range");
                    }
                },
                else => return wrong(path, "integer", category(value)),
            };
            if (fieldConstraints(meta, path)) |constraints| if (numericViolation(constraints, number))
                return constraintFailure(path, "numeric bounds");
        },
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
            if (pointer.child == u8) return validateString(meta, value, path);
            return validateArray(pointer.child, meta, value, path);
        },
        .array => |array| {
            if (array.child == u8) return validateString(meta, value, path);
            return validateArray(array.child, meta, value, path);
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

fn validateString(
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
) ?diagnostic.Diagnostic {
    const text = switch (value) {
        .string => |v| v,
        else => return wrong(path, "string", category(value)),
    };
    if (fieldConstraints(meta, path)) |constraints| {
        if (constraints.min_length) |minimum| if (text.len < minimum) return constraintFailure(path, "minimum string length");
        if (constraints.max_length) |maximum| if (text.len > maximum) return constraintFailure(path, "maximum string length");
    }
    return null;
}

fn validateArray(
    comptime Child: type,
    comptime meta: contract.ToolMeta,
    value: std.json.Value,
    comptime path: []const u8,
) ?diagnostic.Diagnostic {
    const array = switch (value) {
        .array => |v| v,
        else => return wrong(path, "array", category(value)),
    };
    if (fieldConstraints(meta, path)) |constraints| {
        if (constraints.min_items) |minimum| if (array.items.len < minimum) return constraintFailure(path, "minimum array length");
        if (constraints.max_items) |maximum| if (array.items.len > maximum) return constraintFailure(path, "maximum array length");
    }
    for (array.items) |child| if (validateValue(Child, meta, child, path)) |failure| return failure;
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
