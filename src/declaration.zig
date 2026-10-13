const std = @import("std");
const contract = @import("contract.zig");
const derive = @import("derive.zig");
const emit = @import("emit.zig");
const runtime = @import("runtime.zig");

pub fn Tool(comptime function: anytype, comptime metadata: contract.ToolMeta) type {
    return struct {
        pub const handler = function;
        pub const meta = metadata;
        pub const Input = derive.Input(function);
        pub const Host = derive.Host(function);
        pub const Output = derive.Output(function);

        comptime {
            derive.validate(function, metadata);
        }

        pub fn contractJson(allocator: std.mem.Allocator) ![]u8 {
            var out: std.Io.Writer.Allocating = .init(allocator);
            defer out.deinit();
            try emit.json_schema.writeContract(&out.writer, @This());
            return out.toOwnedSlice();
        }

        pub fn emitJson(allocator: std.mem.Allocator, target: emit.Target) ![]u8 {
            var out: std.Io.Writer.Allocating = .init(allocator);
            defer out.deinit();
            try emit.write(&out.writer, @This(), target);
            return out.toOwnedSlice();
        }

        pub fn invoke(allocator: std.mem.Allocator, arguments_json: []const u8) ![]u8 {
            return runtime.dispatch.invoke(function, metadata, allocator, arguments_json);
        }

        pub fn invokeWithHost(
            allocator: std.mem.Allocator,
            arguments_json: []const u8,
            host: Host.?,
        ) ![]u8 {
            return runtime.dispatch.invokeWithHost(function, metadata, allocator, arguments_json, host);
        }
    };
}
