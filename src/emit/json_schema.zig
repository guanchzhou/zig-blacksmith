const std = @import("std");
const common = @import("common.zig");
const contract = @import("../contract.zig");
const diagnostic = @import("../diagnostic.zig");

pub fn project(comptime Tool: type) common.Projection {
    return common.projection(Tool, .json_schema);
}

pub fn diagnose(comptime Tool: type) ?diagnostic.Diagnostic {
    _ = Tool;
    return null;
}

pub fn writeInput(writer: *std.Io.Writer, comptime Tool: type) !void {
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
}

pub fn writeContract(writer: *std.Io.Writer, comptime Tool: type) !void {
    try writer.writeAll("{\"$schema\":");
    try common.writeJsonString(writer, contract.JsonSchemaDialect);
    try writer.writeAll(",\"name\":");
    try common.writeJsonString(writer, Tool.meta.name);
    try writer.writeAll(",\"description\":");
    try common.writeJsonString(writer, Tool.meta.description);
    try writer.writeAll(",\"input\":");
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
    try writer.writeAll(",\"output\":");
    try common.writeSchema(writer, Tool.Output, Tool.meta, null);
    try writer.writeAll(",\"errors\":[");
    inline for (Tool.meta.errors, 0..) |tool_error, i| {
        if (i != 0) try writer.writeAll(",");
        try std.json.Stringify.value(.{
            .code = tool_error.code,
            .message = tool_error.safe_message,
        }, .{}, writer);
    }
    try writer.print(
        "],\"safety\":{{\"readOnly\":{},\"destructive\":{},\"idempotent\":{}}}}}",
        .{ Tool.meta.safety.read_only, Tool.meta.safety.destructive, Tool.meta.safety.idempotent },
    );
}
