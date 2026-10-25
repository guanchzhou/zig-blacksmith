const std = @import("std");
const contract = @import("../contract.zig");
const derive = @import("../derive.zig");
const diagnostic = @import("../diagnostic.zig");

pub const EmitError = error{
    UnsupportedFeature,
    InvalidMetadataJson,
};

pub const Projection = struct {
    target: diagnostic.Target,
    name: []const u8,
    description: []const u8,
    input_type: type,
    output_type: type,
};

pub fn projection(comptime Tool: type, target: diagnostic.Target) Projection {
    return .{
        .target = target,
        .name = Tool.meta.name,
        .description = Tool.meta.description,
        .input_type = Tool.Input,
        .output_type = Tool.Output,
    };
}

pub fn declaredErrorsDiagnostic(comptime Tool: type, target: diagnostic.Target) ?diagnostic.Diagnostic {
    if (Tool.meta.errors.len == 0) return null;
    return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = target,
        .feature = "declared_errors",
        .message = "target tool definitions cannot preserve declared error contracts",
    };
}

pub fn writeJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

pub fn writeSchema(
    writer: *std.Io.Writer,
    comptime T: type,
    comptime meta: contract.ToolMeta,
    comptime field_meta: ?contract.FieldMeta,
) !void {
    try writeSchemaAt(writer, T, meta, field_meta, "");
}

fn writeSchemaAt(
    writer: *std.Io.Writer,
    comptime T: type,
    comptime meta: contract.ToolMeta,
    comptime field_meta: ?contract.FieldMeta,
    comptime path: []const u8,
) !void {
    switch (@typeInfo(T)) {
        .bool => try writer.writeAll("{\"type\":\"boolean\"}"),
        .int => try writeInteger(writer, T, field_meta),
        .float, .comptime_float => try writeNumber(writer, field_meta),
        .void => try writer.writeAll("{\"type\":\"null\"}"),
        .optional => |optional| {
            try writer.writeAll("{\"anyOf\":[");
            try writeSchemaAt(writer, optional.child, meta, field_meta, path);
            try writer.writeAll(",{\"type\":\"null\"}]}");
        },
        .pointer => |pointer| {
            if (pointer.size == .slice and pointer.child == u8) {
                try writeString(writer, field_meta, null);
            } else if (pointer.size == .slice) {
                try writeArray(writer, pointer.child, meta, field_meta, path, null);
            } else unreachable;
        },
        .array => |array| {
            if (array.child == u8) {
                try writeString(writer, field_meta, array.len);
            } else {
                try writeArray(writer, array.child, meta, field_meta, path, array.len);
            }
        },
        .@"enum" => |enumeration| {
            try writer.writeAll("{\"type\":\"string\",\"enum\":[");
            inline for (enumeration.field_names, 0..) |name, i| {
                if (i != 0) try writer.writeAll(",");
                try writeJsonString(writer, name);
            }
            try writer.writeAll("]");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
        },
        .@"struct" => |object| {
            try writer.writeAll("{\"type\":\"object\",\"properties\":{");
            inline for (object.field_names, object.field_types, 0..) |name, field_type, i| {
                if (i != 0) try writer.writeAll(",");
                try writeJsonString(writer, name);
                try writer.writeAll(":");
                const child_path = if (path.len == 0) name else path ++ "." ++ name;
                try writeSchemaAt(writer, field_type, meta, derive.fieldMeta(meta, child_path), child_path);
            }
            try writer.writeAll("},\"required\":[");
            var wrote_required = false;
            inline for (object.field_names, object.field_types, 0..) |name, field_type, i| {
                const child_path = if (path.len == 0) name else path ++ "." ++ name;
                const fm = derive.fieldMeta(meta, child_path);
                if (!derive.isOptional(field_type) and !derive.hasDefault(T, i) and fm.default_json == null) {
                    if (wrote_required) try writer.writeAll(",");
                    try writeJsonString(writer, name);
                    wrote_required = true;
                }
            }
            try writer.writeAll("],\"additionalProperties\":false}");
        },
        .@"union" => |union_info| {
            try writer.writeAll("{\"oneOf\":[");
            inline for (union_info.field_names, union_info.field_types, 0..) |name, payload, i| {
                if (i != 0) try writer.writeAll(",");
                try writer.writeAll("{\"type\":\"object\",\"properties\":{");
                try writeJsonString(writer, name);
                try writer.writeAll(":");
                const child_path = if (path.len == 0) name else path ++ "." ++ name;
                try writeSchemaAt(writer, payload, meta, null, child_path);
                try writer.writeAll("},\"required\":[");
                try writeJsonString(writer, name);
                try writer.writeAll("],\"additionalProperties\":false}");
            }
            try writer.writeAll("]}");
        },
        else => unreachable,
    }
}

pub fn containsTaggedUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"union" => true,
        .optional => |o| containsTaggedUnion(o.child),
        .array => |a| containsTaggedUnion(a.child),
        .pointer => |p| p.size == .slice and p.child != u8 and containsTaggedUnion(p.child),
        .@"struct" => |s| blk: {
            inline for (s.field_types) |field_type| if (containsTaggedUnion(field_type)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

pub fn validateRawJson(comptime raw: []const u8) EmitError!void {
    if (!(std.json.Scanner.validate(std.heap.page_allocator, raw) catch false))
        return error.InvalidMetadataJson;
}

fn writeInteger(writer: *std.Io.Writer, comptime T: type, comptime field_meta: ?contract.FieldMeta) !void {
    const constraints = if (field_meta) |fm| fm.constraints else contract.Constraints{};
    const bounds = comptime derive.integerBounds(T, constraints);
    try writer.print("{{\"type\":\"integer\",\"minimum\":{d},\"maximum\":{d}", .{ bounds.min, bounds.max });
    try writeDescriptionAndExample(writer, field_meta);
    try writer.writeAll("}");
}

fn writeNumber(writer: *std.Io.Writer, comptime field_meta: ?contract.FieldMeta) !void {
    try writer.writeAll("{\"type\":\"number\"");
    if (field_meta) |fm| {
        if (fm.constraints.minimum) |minimum| try writer.print(",\"minimum\":{d}", .{minimum});
        if (fm.constraints.maximum) |maximum| try writer.print(",\"maximum\":{d}", .{maximum});
    }
    try writeDescriptionAndExample(writer, field_meta);
    try writer.writeAll("}");
}

fn writeString(writer: *std.Io.Writer, comptime field_meta: ?contract.FieldMeta, comptime fixed_len: ?usize) !void {
    try writer.writeAll("{\"type\":\"string\"");
    if (fixed_len) |len| try writer.print(",\"minLength\":{d},\"maxLength\":{d}", .{ len, len });
    if (field_meta) |fm| {
        if (fm.constraints.min_length) |minimum| try writer.print(",\"minLength\":{d}", .{minimum});
        if (fm.constraints.max_length) |maximum| try writer.print(",\"maxLength\":{d}", .{maximum});
        if (fm.constraints.pattern) |pattern| {
            try writer.writeAll(",\"pattern\":");
            try writeJsonString(writer, pattern);
        }
    }
    try writeDescriptionAndExample(writer, field_meta);
    try writer.writeAll("}");
}

fn writeArray(
    writer: *std.Io.Writer,
    comptime Child: type,
    comptime meta: contract.ToolMeta,
    comptime field_meta: ?contract.FieldMeta,
    comptime path: []const u8,
    comptime fixed_len: ?usize,
) !void {
    try writer.writeAll("{\"type\":\"array\",\"items\":");
    try writeSchemaAt(writer, Child, meta, null, path ++ "[]");
    if (fixed_len) |len| try writer.print(",\"minItems\":{d},\"maxItems\":{d}", .{ len, len });
    if (field_meta) |fm| {
        if (fm.constraints.min_items) |minimum| try writer.print(",\"minItems\":{d}", .{minimum});
        if (fm.constraints.max_items) |maximum| try writer.print(",\"maxItems\":{d}", .{maximum});
    }
    try writeDescriptionAndExample(writer, field_meta);
    try writer.writeAll("}");
}

fn writeDescriptionAndExample(writer: *std.Io.Writer, comptime field_meta: ?contract.FieldMeta) !void {
    if (field_meta) |fm| {
        if (fm.description.len != 0) {
            try writer.writeAll(",\"description\":");
            try writeJsonString(writer, fm.description);
        }
        if (fm.default_json) |raw| {
            try validateRawJson(raw);
            try writer.writeAll(",\"default\":");
            try writer.writeAll(raw);
        }
        if (fm.example_json) |raw| {
            try validateRawJson(raw);
            try writer.writeAll(",\"examples\":[");
            try writer.writeAll(raw);
            try writer.writeAll("]");
        }
    }
}
