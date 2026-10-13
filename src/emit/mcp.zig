const std = @import("std");
const common = @import("common.zig");
const contract = @import("../contract.zig");
const diagnostic = @import("../diagnostic.zig");

pub const live_sdk_integration = false;
pub const live_sdk_gate_reason = "zig-mcp-sdk 0.5.0 targets Zig 0.16 and exposes parsed arguments instead of raw JSON";

pub fn project(comptime Tool: type) common.Projection {
    return common.projection(Tool, .mcp);
}

pub fn diagnose(comptime Tool: type) ?diagnostic.Diagnostic {
    return common.declaredErrorsDiagnostic(Tool, .mcp);
}

pub fn write(writer: *std.Io.Writer, comptime Tool: type) !void {
    if (diagnose(Tool) != null) return error.UnsupportedFeature;
    try writer.writeAll("{\"name\":");
    try common.writeJsonString(writer, Tool.meta.name);
    try writer.writeAll(",\"description\":");
    try common.writeJsonString(writer, Tool.meta.description);
    try writer.writeAll(",\"inputSchema\":");
    try common.writeSchema(writer, Tool.Input, Tool.meta, null);
    try writer.writeAll(",\"outputSchema\":");
    try common.writeSchema(writer, Tool.Output, Tool.meta, null);
    try writer.print(
        ",\"annotations\":{{\"readOnlyHint\":{},\"destructiveHint\":{},\"idempotentHint\":{}}}}}",
        .{ Tool.meta.safety.read_only, Tool.meta.safety.destructive, Tool.meta.safety.idempotent },
    );
}

pub fn negotiate(version: []const u8) ?diagnostic.Diagnostic {
    if (std.mem.eql(u8, version, contract.McpProtocolVersion)) return null;
    return .{
        .stage = .protocol,
        .code = .protocol_mismatch,
        .target = .mcp,
        .expected = contract.McpProtocolVersion,
        .actual_category = "unsupported_protocol_version",
        .message = "MCP protocol version is not supported",
    };
}

test "MCP negotiation is pinned" {
    try std.testing.expect(!live_sdk_integration);
    try std.testing.expect(live_sdk_gate_reason.len != 0);
    try std.testing.expect(negotiate(contract.McpProtocolVersion) == null);
    try std.testing.expectEqual(diagnostic.Code.protocol_mismatch, negotiate("2025-11-25").?.code);
}
