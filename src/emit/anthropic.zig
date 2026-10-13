const std = @import("std");
const common = @import("common.zig");
const diagnostic = @import("../diagnostic.zig");

pub fn project(comptime Tool: type) common.Projection {
    return common.projection(Tool, .anthropic);
}

pub fn diagnose(comptime Tool: type) ?diagnostic.Diagnostic {
    if (common.declaredErrorsDiagnostic(Tool, .anthropic)) |failure| return failure;
    if (Tool.meta.safety.any()) return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = .anthropic,
        .feature = "safety",
        .message = "Anthropic tool definitions cannot preserve MCP safety annotations",
    };
    if (Tool.Output != void) return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = .anthropic,
        .feature = "output_schema",
        .message = "Anthropic tool definitions do not declare output schemas",
    };
    return null;
}

pub fn write(writer: *std.Io.Writer, comptime Tool: type) !void {
    if (diagnose(Tool) != null) return error.UnsupportedFeature;
    try writer.writeAll("{\"name\":");
    try common.writeJsonString(writer, Tool.meta.name);
    try writer.writeAll(",\"description\":");
    try common.writeJsonString(writer, Tool.meta.description);
    try writer.writeAll(",\"strict\":true,\"input_schema\":");
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
    try writer.writeAll("}");
}
