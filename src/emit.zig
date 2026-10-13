pub const common = @import("emit/common.zig");
pub const json_schema = @import("emit/json_schema.zig");
pub const openai = @import("emit/openai.zig");
pub const anthropic = @import("emit/anthropic.zig");
pub const gemini = @import("emit/gemini.zig");
pub const mcp = @import("emit/mcp.zig");

pub const Target = enum {
    json_schema,
    openai,
    anthropic,
    gemini,
    mcp,

    pub fn parse(value: []const u8) ?Target {
        const std = @import("std");
        inline for (@typeInfo(Target).@"enum".field_names) |name| {
            const cli_name = if (comptime std.mem.eql(u8, name, "json_schema")) "json-schema" else name;
            if (std.mem.eql(u8, value, cli_name)) return @field(Target, name);
        }
        return null;
    }
};

pub fn diagnose(comptime Tool: type, target: Target) ?@import("diagnostic.zig").Diagnostic {
    return switch (target) {
        .json_schema => json_schema.diagnose(Tool),
        .openai => openai.diagnose(Tool),
        .anthropic => anthropic.diagnose(Tool),
        .gemini => gemini.diagnose(Tool),
        .mcp => mcp.diagnose(Tool),
    };
}

pub fn write(writer: *@import("std").Io.Writer, comptime Tool: type, target: Target) !void {
    switch (target) {
        .json_schema => try json_schema.writeInput(writer, Tool),
        .openai => try openai.write(writer, Tool),
        .anthropic => try anthropic.write(writer, Tool),
        .gemini => try gemini.write(writer, Tool),
        .mcp => try mcp.write(writer, Tool),
    }
}
