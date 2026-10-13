const std = @import("std");
const common = @import("common.zig");
const diagnostic = @import("../diagnostic.zig");

pub fn project(comptime Tool: type) common.Projection {
    return common.projection(Tool, .gemini);
}

pub fn diagnose(comptime Tool: type) ?diagnostic.Diagnostic {
    if (common.declaredErrorsDiagnostic(Tool, .gemini)) |failure| return failure;
    if (Tool.meta.safety.any()) return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = .gemini,
        .feature = "safety",
        .message = "Gemini function declarations cannot preserve MCP safety annotations",
    };
    if (common.containsTaggedUnion(Tool.Input) or common.containsTaggedUnion(Tool.Output)) return .{
        .stage = .emission,
        .code = .lossy_mapping,
        .target = .gemini,
        .feature = "tagged_union",
        .message = "Gemini's supported schema subset cannot preserve tagged unions",
    };
    return null;
}

pub fn write(writer: *std.Io.Writer, comptime Tool: type) !void {
    if (diagnose(Tool) != null) return error.UnsupportedFeature;
    try writer.writeAll("{\"name\":");
    try common.writeJsonString(writer, Tool.meta.name);
    try writer.writeAll(",\"description\":");
    try common.writeJsonString(writer, Tool.meta.description);
    try writer.writeAll(",\"parametersJsonSchema\":");
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
    try writer.writeAll(",\"responseJsonSchema\":");
    try common.writeSchema(writer, Tool.Output, Tool.meta, null);
    try writer.writeAll("}");
}
