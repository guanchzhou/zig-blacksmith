const std = @import("std");
const emit = @import("emit.zig");
const diagnostic = @import("diagnostic.zig");

pub fn Registry(comptime tools: anytype) type {
    comptime {
        for (tools, 0..) |Tool, i| {
            for (tools, 0..) |Earlier, j| {
                if (j < i and std.mem.eql(u8, Tool.meta.name, Earlier.meta.name))
                    @compileError("blacksmith registry contains duplicate tool names");
            }
        }
    }

    return struct {
        pub const all = tools;

        pub fn contains(name: []const u8) bool {
            inline for (tools) |Tool| if (std.mem.eql(u8, name, Tool.meta.name)) return true;
            return false;
        }

        pub fn writeContract(writer: *std.Io.Writer, name: []const u8) !bool {
            inline for (tools) |Tool| {
                if (std.mem.eql(u8, name, Tool.meta.name)) {
                    try emit.json_schema.writeContract(writer, Tool);
                    return true;
                }
            }
            return false;
        }

        pub fn writeTarget(writer: *std.Io.Writer, name: []const u8, target: emit.Target) !bool {
            inline for (tools) |Tool| {
                if (std.mem.eql(u8, name, Tool.meta.name)) {
                    try emit.write(writer, Tool, target);
                    return true;
                }
            }
            return false;
        }

        pub fn diagnose(name: []const u8, target: emit.Target) ?diagnostic.Diagnostic {
            inline for (tools) |Tool| if (std.mem.eql(u8, name, Tool.meta.name)) return emit.diagnose(Tool, target);
            return null;
        }

        pub fn checkAll(writer: *std.Io.Writer) !bool {
            var ok = true;
            inline for (tools) |Tool| {
                inline for (@typeInfo(emit.Target).@"enum".field_names) |target_name| {
                    const target = @field(emit.Target, target_name);
                    if (emit.diagnose(Tool, target)) |failure| {
                        ok = false;
                        try failure.writeJson(writer);
                        try writer.writeAll("\n");
                    }
                }
            }
            return ok;
        }
    };
}
