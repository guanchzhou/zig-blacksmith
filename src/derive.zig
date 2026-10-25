const std = @import("std");
const contract = @import("contract.zig");

pub fn Input(comptime handler: anytype) type {
    const info = functionInfo(handler);
    if (info.param_types.len == 0 or info.param_types.len > 2)
        @compileError("blacksmith handlers require one input parameter and may have one host-injected parameter");
    return info.param_types[0] orelse
        @compileError("blacksmith handlers cannot use generic input parameters");
}

pub fn Host(comptime handler: anytype) ?type {
    const params = functionInfo(handler).param_types;
    if (params.len < 2) return null;
    return params[1] orelse
        @compileError("blacksmith handlers cannot use generic host parameters");
}

pub fn Return(comptime handler: anytype) type {
    return functionInfo(handler).return_type orelse
        @compileError("blacksmith handlers must have a return type");
}

pub fn Output(comptime handler: anytype) type {
    const T = Return(handler);
    return switch (@typeInfo(T)) {
        .error_union => |eu| eu.payload,
        else => T,
    };
}

pub fn validate(comptime handler: anytype, comptime meta: contract.ToolMeta) void {
    validateName(meta.name);
    if (meta.description.len == 0) @compileError("blacksmith tool descriptions cannot be empty");
    const input = Input(handler);
    if (@typeInfo(input) != .@"struct")
        @compileError("blacksmith tool input must be a struct");
    validateType(input, "$", true);
    validateType(Output(handler), "$result", false);

    inline for (meta.fields) |field_meta| {
        if (!pathExists(input, field_meta.name))
            @compileError("blacksmith field metadata names a field path that does not exist");
        validateConstraints(FieldType(input, field_meta.name), field_meta.constraints);
    }

    inline for (meta.errors) |tool_error| {
        if (tool_error.zig_name.len == 0 or tool_error.code.len == 0 or tool_error.safe_message.len == 0)
            @compileError("blacksmith declared errors require zig_name, code, and safe_message");
    }
}

pub fn kind(comptime T: type) contract.NodeKind {
    return switch (@typeInfo(T)) {
        .bool => .boolean,
        .int => .integer,
        .float, .comptime_float => .number,
        .optional => .optional,
        .@"enum" => .enumeration,
        .@"struct" => .object,
        .@"union" => .tagged_union,
        .void => .void,
        .pointer => |p| if (p.size == .slice and p.child == u8) .string else if (p.size == .slice) .array else unsupported(T),
        .array => |a| if (a.child == u8) .string else .array,
        else => unsupported(T),
    };
}

pub fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

pub fn hasDefault(comptime Struct: type, comptime index: usize) bool {
    const info = @typeInfo(Struct).@"struct";
    return info.field_attrs[index].defaultValue(info.field_types[index]) != null;
}

pub fn fieldMeta(comptime meta: contract.ToolMeta, comptime name: []const u8) contract.FieldMeta {
    return contract.field(meta, name) orelse .{ .name = name };
}

fn functionInfo(comptime handler: anytype) std.builtin.Type.Fn {
    return switch (@typeInfo(@TypeOf(handler))) {
        .@"fn" => |info| info,
        else => @compileError("blacksmith declarations must bind a function"),
    };
}

fn validateName(comptime name: []const u8) void {
    if (name.len == 0 or name.len > 64)
        @compileError("blacksmith tool names must contain 1 to 64 characters");
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-'))
            @compileError("blacksmith tool names may contain only letters, digits, underscores, and dashes");
    }
}

fn validateConstraints(comptime Field: type, comptime c: contract.Constraints) void {
    if (c.pattern != null)
        @compileError("blacksmith 0.1 does not support runtime pattern validation");
    const numeric = c.minimum != null or c.maximum != null;
    const length = c.min_length != null or c.max_length != null;
    const items = c.min_items != null or c.max_items != null;
    const T = Unwrapped(Field);
    switch (kind(T)) {
        .integer, .number => {
            if (length or items) @compileError("blacksmith length and item constraints apply only to strings and arrays");
        },
        .string => {
            if (numeric or items) @compileError("blacksmith string fields accept only min_length and max_length");
            if (length and @typeInfo(T) == .array) @compileError("blacksmith fixed-length arrays take their length from the type");
        },
        .array => {
            if (numeric or length) @compileError("blacksmith array fields accept only min_items and max_items");
            if (items and @typeInfo(T) == .array) @compileError("blacksmith fixed-length arrays take their length from the type");
        },
        else => if (numeric or length or items) @compileError("blacksmith constraints apply only to numbers, strings, and arrays"),
    }
    if (c.minimum) |minimum| if (!std.math.isFinite(minimum)) @compileError("blacksmith field minimum must be finite");
    if (c.maximum) |maximum| if (!std.math.isFinite(maximum)) @compileError("blacksmith field maximum must be finite");
    if (c.minimum != null and c.maximum != null and c.minimum.? > c.maximum.?)
        @compileError("blacksmith field minimum cannot exceed maximum");
    if (@typeInfo(T) == .int) _ = integerBounds(T, c);
    if (c.min_length != null and c.max_length != null and c.min_length.? > c.max_length.?)
        @compileError("blacksmith field min_length cannot exceed max_length");
    if (c.min_items != null and c.max_items != null and c.min_items.? > c.max_items.?)
        @compileError("blacksmith field min_items cannot exceed max_items");
}

pub fn Wide(comptime T: type) type {
    return @Int(.signed, @max(128, @typeInfo(T).int.bits + 1));
}

pub fn IntegerBounds(comptime T: type) type {
    return struct { min: Wide(T), max: Wide(T) };
}

pub fn integerBounds(comptime T: type, comptime c: contract.Constraints) IntegerBounds(T) {
    const W = Wide(T);
    const low: W = std.math.minInt(T);
    const high: W = std.math.maxInt(T);
    var bounds: IntegerBounds(T) = .{ .min = low, .max = high };
    if (c.minimum) |minimum| {
        if (minimum > @as(f64, @floatFromInt(high)))
            @compileError("blacksmith field minimum exceeds the range of its integer type");
        if (minimum > @as(f64, @floatFromInt(low))) bounds.min = @intFromFloat(@ceil(minimum));
    }
    if (c.maximum) |maximum| {
        if (maximum < @as(f64, @floatFromInt(low)))
            @compileError("blacksmith field maximum is below the range of its integer type");
        if (maximum < @as(f64, @floatFromInt(high))) bounds.max = @intFromFloat(@floor(maximum));
    }
    if (bounds.min > bounds.max) @compileError("blacksmith integer field bounds admit no value");
    return bounds;
}

pub fn Unwrapped(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |optional| Unwrapped(optional.child),
        else => T,
    };
}

pub fn FieldType(comptime T: type, comptime path: []const u8) type {
    const info = @typeInfo(Unwrapped(T)).@"struct";
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (comptime contract.eql(segment, field_name)) {
            if (dot) |index| return FieldType(field_type, path[index + 1 ..]);
            return field_type;
        }
    }
    @compileError("blacksmith field metadata names a field path that does not exist");
}

fn validateType(comptime T: type, comptime path: []const u8, comptime allow_error_union: bool) void {
    switch (@typeInfo(T)) {
        .bool, .int, .float, .comptime_float, .void, .@"enum" => {},
        .optional => |o| validateType(o.child, path, false),
        .array => |a| validateType(a.child, path, false),
        .pointer => |p| {
            if (p.size != .slice) @compileError("blacksmith does not support non-slice pointer fields");
            validateType(p.child, path, false);
        },
        .@"struct" => |s| inline for (s.field_types) |field_type| validateType(field_type, path, false),
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("blacksmith requires tagged unions");
            inline for (u.field_types) |field_type| validateType(field_type, path, false);
        },
        .error_union => |eu| {
            if (!allow_error_union) @compileError("blacksmith supports error unions only as handler return types");
            validateType(eu.payload, path, false);
        },
        else => @compileError("blacksmith encountered an unsupported Zig type"),
    }
}

fn pathExists(comptime T: type, comptime path: []const u8) bool {
    const unwrapped = switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
    const info = switch (@typeInfo(unwrapped)) {
        .@"struct" => |object| object,
        else => return false,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (comptime contract.eql(segment, field_name)) {
            if (dot) |index| return pathExists(field_type, path[index + 1 ..]);
            return true;
        }
    }
    return false;
}

fn unsupported(comptime T: type) noreturn {
    _ = T;
    @compileError("blacksmith encountered an unsupported Zig type");
}

test "derives handler input and output" {
    const In = struct { value: i32 };
    const f = struct {
        fn call(input: In) error{Bad}!u32 {
            if (input.value < 0) return error.Bad;
            return @intCast(input.value);
        }
    }.call;
    try std.testing.expect(Input(f) == In);
    try std.testing.expect(Output(f) == u32);
}
