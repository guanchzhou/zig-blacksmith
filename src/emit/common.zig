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
        .bool => {
            try writer.writeAll("{\"type\":\"boolean\"");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
        },
        .int => try writeInteger(writer, T, field_meta),
        .float, .comptime_float => try writeNumber(writer, field_meta),
        .void => {
            try writer.writeAll("{\"type\":\"null\"");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
        },
        .optional => |optional| {
            const inner_meta: ?contract.FieldMeta = if (field_meta) |fm| .{
                .name = fm.name,
                .constraints = fm.constraints,
            } else null;
            try writer.writeAll("{\"anyOf\":[");
            try writeSchemaAt(writer, optional.child, meta, inner_meta, path);
            try writer.writeAll(",{\"type\":\"null\"}]");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
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
            try writer.writeAll("],\"additionalProperties\":false");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
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
            try writer.writeAll("]");
            try writeDescriptionAndExample(writer, field_meta);
            try writer.writeAll("}");
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
    if (comptime !isValidJsonComptime(raw)) return error.InvalidMetadataJson;
}

const ComptimeJsonValidator = struct {
    input: []const u8,
    pos: usize = 0,

    const max_depth: usize = 64;

    fn skipWs(self: *ComptimeJsonValidator) void {
        while (self.pos < self.input.len) : (self.pos += 1) {
            switch (self.input[self.pos]) {
                ' ', '\t', '\r', '\n' => {},
                else => break,
            }
        }
    }

    fn parseValue(self: *ComptimeJsonValidator, depth: usize) bool {
        if (depth > max_depth) return false;
        self.skipWs();
        if (self.pos >= self.input.len) return false;
        return switch (self.input[self.pos]) {
            '"' => self.parseString(),
            '{' => self.parseObject(depth + 1),
            '[' => self.parseArray(depth + 1),
            't' => self.expectLiteral("true"),
            'f' => self.expectLiteral("false"),
            'n' => self.expectLiteral("null"),
            '-', '0'...'9' => self.parseNumber(),
            else => false,
        };
    }

    fn expectLiteral(self: *ComptimeJsonValidator, literal: []const u8) bool {
        if (self.pos + literal.len > self.input.len) return false;
        if (!std.mem.eql(u8, self.input[self.pos..][0..literal.len], literal)) return false;
        self.pos += literal.len;
        return true;
    }

    fn parseHex4(self: *ComptimeJsonValidator) ?u16 {
        if (self.pos + 4 > self.input.len) return null;
        var out: u16 = 0;
        for (self.input[self.pos..][0..4]) |c| {
            const digit: u16 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'f' => c - 'a' + 10,
                'A'...'F' => c - 'A' + 10,
                else => return null,
            };
            out = (out << 4) | digit;
        }
        self.pos += 4;
        return out;
    }

    fn parseString(self: *ComptimeJsonValidator) bool {
        if (self.pos >= self.input.len or self.input[self.pos] != '"') return false;
        self.pos += 1;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '"') {
                self.pos += 1;
                return true;
            }
            if (c < 0x20) return false;
            if (c == '\\') {
                self.pos += 1;
                if (self.pos >= self.input.len) return false;
                switch (self.input[self.pos]) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.pos += 1,
                    'u' => {
                        self.pos += 1;
                        const code = self.parseHex4() orelse return false;
                        if (code >= 0xD800 and code <= 0xDBFF) {
                            if (self.pos + 2 > self.input.len or self.input[self.pos] != '\\' or self.input[self.pos + 1] != 'u') return false;
                            self.pos += 2;
                            const low = self.parseHex4() orelse return false;
                            if (low < 0xDC00 or low > 0xDFFF) return false;
                        } else if (code >= 0xDC00 and code <= 0xDFFF) {
                            return false;
                        }
                    },
                    else => return false,
                }
            } else if (c < 0x80) {
                self.pos += 1;
            } else {
                const len = std.unicode.utf8ByteSequenceLength(c) catch return false;
                if (self.pos + len > self.input.len) return false;
                _ = std.unicode.utf8Decode(self.input[self.pos..][0..len]) catch return false;
                self.pos += len;
            }
        }
        return false;
    }

    fn parseNumber(self: *ComptimeJsonValidator) bool {
        if (self.pos < self.input.len and self.input[self.pos] == '-') self.pos += 1;
        if (self.pos >= self.input.len) return false;
        if (self.input[self.pos] == '0') {
            self.pos += 1;
        } else if (self.input[self.pos] >= '1' and self.input[self.pos] <= '9') {
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') self.pos += 1;
        } else {
            return false;
        }
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            self.pos += 1;
            const frac_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') self.pos += 1;
            if (self.pos == frac_start) return false;
        }
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) self.pos += 1;
            const exp_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') self.pos += 1;
            if (self.pos == exp_start) return false;
        }
        return true;
    }

    fn parseObject(self: *ComptimeJsonValidator, depth: usize) bool {
        self.pos += 1;
        self.skipWs();
        if (self.pos < self.input.len and self.input[self.pos] == '}') {
            self.pos += 1;
            return true;
        }
        while (true) {
            self.skipWs();
            if (!self.parseString()) return false;
            self.skipWs();
            if (self.pos >= self.input.len or self.input[self.pos] != ':') return false;
            self.pos += 1;
            if (!self.parseValue(depth)) return false;
            self.skipWs();
            if (self.pos >= self.input.len) return false;
            if (self.input[self.pos] == '}') {
                self.pos += 1;
                return true;
            }
            if (self.input[self.pos] != ',') return false;
            self.pos += 1;
        }
    }

    fn parseArray(self: *ComptimeJsonValidator, depth: usize) bool {
        self.pos += 1;
        self.skipWs();
        if (self.pos < self.input.len and self.input[self.pos] == ']') {
            self.pos += 1;
            return true;
        }
        while (true) {
            if (!self.parseValue(depth)) return false;
            self.skipWs();
            if (self.pos >= self.input.len) return false;
            if (self.input[self.pos] == ']') {
                self.pos += 1;
                return true;
            }
            if (self.input[self.pos] != ',') return false;
            self.pos += 1;
        }
    }
};

fn isValidJsonComptime(comptime raw: []const u8) bool {
    @setEvalBranchQuota(@max(10_000, raw.len * 64));
    var validator: ComptimeJsonValidator = .{ .input = raw };
    if (!validator.parseValue(0)) return false;
    validator.skipWs();
    return validator.pos == raw.len;
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
