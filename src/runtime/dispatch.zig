const std = @import("std");
const contract = @import("../contract.zig");
const derive = @import("../derive.zig");
const diagnostic = @import("../diagnostic.zig");
const decode = @import("decode.zig");

pub fn invoke(
    comptime handler: anytype,
    comptime meta: contract.ToolMeta,
    allocator: std.mem.Allocator,
    arguments_json: []const u8,
) ![]u8 {
    if (derive.Host(handler) != null)
        @compileError("use invokeWithHost for handlers with a host-injected parameter");
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const decoded = try decode.decode(derive.Input(handler), meta, arena, arguments_json);
    return switch (decoded) {
        .invalid => |failure| writeValidation(allocator, failure),
        .ok => |input| callWithoutHost(handler, meta, allocator, input),
    };
}

pub fn invokeWithHost(
    comptime handler: anytype,
    comptime meta: contract.ToolMeta,
    allocator: std.mem.Allocator,
    arguments_json: []const u8,
    host: derive.Host(handler).?,
) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const decoded = try decode.decode(derive.Input(handler), meta, arena, arguments_json);
    return switch (decoded) {
        .invalid => |failure| writeValidation(allocator, failure),
        .ok => |input| callWithHost(handler, meta, allocator, input, host),
    };
}

fn callWithoutHost(
    comptime handler: anytype,
    comptime meta: contract.ToolMeta,
    allocator: std.mem.Allocator,
    input: derive.Input(handler),
) ![]u8 {
    const Return = derive.Return(handler);
    return switch (@typeInfo(Return)) {
        .error_union => blk: {
            const output = handler(input) catch |err| break :blk writeToolError(meta, allocator, err);
            break :blk writeSuccess(allocator, output);
        },
        else => writeSuccess(allocator, handler(input)),
    };
}

fn callWithHost(
    comptime handler: anytype,
    comptime meta: contract.ToolMeta,
    allocator: std.mem.Allocator,
    input: derive.Input(handler),
    host: derive.Host(handler).?,
) ![]u8 {
    const Return = derive.Return(handler);
    return switch (@typeInfo(Return)) {
        .error_union => blk: {
            const output = handler(input, host) catch |err| break :blk writeToolError(meta, allocator, err);
            break :blk writeSuccess(allocator, output);
        },
        else => writeSuccess(allocator, handler(input, host)),
    };
}

fn writeSuccess(allocator: std.mem.Allocator, output: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("{\"kind\":\"success\",\"output\":");
    if (@TypeOf(output) == void) {
        try out.writer.writeAll("null");
    } else {
        try std.json.Stringify.value(output, .{}, &out.writer);
    }
    try out.writer.writeAll("}");
    return out.toOwnedSlice();
}

fn writeToolError(comptime meta: contract.ToolMeta, allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    const name = @errorName(err);
    if (contract.declaredError(meta, name)) |declared| {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try out.writer.writeAll("{\"kind\":\"tool_error\",\"code\":");
        try std.json.Stringify.value(declared.code, .{}, &out.writer);
        try out.writer.writeAll(",\"message\":");
        try std.json.Stringify.value(declared.safe_message, .{}, &out.writer);
        try out.writer.writeAll("}");
        return out.toOwnedSlice();
    }
    return writeInternal(allocator);
}

fn writeValidation(allocator: std.mem.Allocator, failure: diagnostic.Diagnostic) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("{\"kind\":\"validation_error\",\"error\":");
    try failure.writeJson(&out.writer);
    try out.writer.writeAll("}");
    return out.toOwnedSlice();
}

fn writeInternal(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"kind\":\"internal_error\",\"code\":\"internal_error\",\"message\":\"tool execution failed\"}}",
        .{},
    );
}
