const std = @import("std");
const common = @import("common.zig");
const diagnostic = @import("../diagnostic.zig");

pub fn project(comptime Tool: type) common.Projection {
    return common.projection(Tool, .openai);
}

pub fn diagnose(comptime Tool: type) ?diagnostic.Diagnostic {
    if (common.declaredErrorsDiagnostic(Tool, .openai)) |failure| return failure;
    if (Tool.meta.safety.any()) return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = .openai,
        .feature = "safety",
        .message = "OpenAI function tools cannot preserve MCP safety annotations",
    };
    return null;
}

pub fn write(writer: *std.Io.Writer, comptime Tool: type) !void {
    if (diagnose(Tool) != null) return error.UnsupportedFeature;
    try writer.writeAll("{\"type\":\"function\",\"name\":");
    try common.writeJsonString(writer, Tool.meta.name);
    try writer.writeAll(",\"description\":");
    try common.writeJsonString(writer, Tool.meta.description);
    try writer.writeAll(",\"strict\":false,\"parameters\":");
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
    try writer.writeAll(",\"output_schema\":");
    try common.writeSchema(writer, Tool.Output, Tool.meta, null);
    try writer.writeAll("}");
}
