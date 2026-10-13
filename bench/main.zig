const std = @import("std");
const tools = @import("tool_registry");

const iterations = 10_000;

const CountingAllocator = struct {
    child: std.mem.Allocator,
    allocations: usize = 0,
    requested_bytes: usize = 0,

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const memory = self.child.vtable.alloc(self.child.ptr, len, alignment, return_address);
        if (memory != null) {
            self.allocations += 1;
            self.requested_bytes += len;
        }
        return memory;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        return self.child.vtable.resize(self.child.ptr, memory, alignment, new_len, return_address);
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        return self.child.vtable.remap(self.child.ptr, memory, alignment, new_len, return_address);
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.child.vtable.free(self.child.ptr, memory, alignment, return_address);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    defer stdout.interface.flush() catch {};

    const schema_start = std.Io.Clock.Timestamp.now(init.io, .awake);
    for (0..iterations) |_| {
        const rendered = try tools.Weather.contractJson(allocator);
        allocator.free(rendered);
    }
    const schema_ns = schema_start.untilNow(init.io).raw.nanoseconds;

    const dispatch_start = std.Io.Clock.Timestamp.now(init.io, .awake);
    for (0..iterations) |_| {
        const result = try tools.Scale.invoke(allocator, "{\"value\":2}");
        allocator.free(result);
    }
    const dispatch_ns = dispatch_start.untilNow(init.io).raw.nanoseconds;

    const rejection_start = std.Io.Clock.Timestamp.now(init.io, .awake);
    for (0..iterations) |_| {
        const result = try tools.Weather.invoke(
            allocator,
            "{\"location\":\"Helsinki\",\"options\":{\"language\":\"this-language-name-is-too-long\"}}",
        );
        allocator.free(result);
    }
    const rejection_ns = rejection_start.untilNow(init.io).raw.nanoseconds;

    const emitted = try tools.Weather.emitJson(allocator, .mcp);
    defer allocator.free(emitted);
    var counter: CountingAllocator = .{ .child = allocator };
    const counted_result = try tools.Scale.invoke(counter.allocator(), "{\"value\":2}");
    counter.allocator().free(counted_result);
    try stdout.interface.print(
        "{{\"iterations\":{d},\"schema_ns_per_op\":{d},\"dispatch_ns_per_op\":{d},\"nested_rejection_ns_per_op\":{d},\"dispatch_allocations\":{d},\"dispatch_requested_bytes\":{d},\"mcp_schema_bytes\":{d}}}\n",
        .{
            iterations,
            @divTrunc(schema_ns, iterations),
            @divTrunc(dispatch_ns, iterations),
            @divTrunc(rejection_ns, iterations),
            counter.allocations,
            counter.requested_bytes,
            emitted.len,
        },
    );
}
