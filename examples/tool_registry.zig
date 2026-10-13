const std = @import("std");
const blacksmith = @import("blacksmith");

pub const Unit = enum { celsius, fahrenheit };
pub const WeatherOptions = struct {
    language: ?[]const u8 = null,
};

pub const ScaleInput = struct { value: i32 };
fn scale(input: ScaleInput) i32 {
    return input.value * 2;
}
pub const Scale = blacksmith.Tool(scale, .{
    .name = "scale",
    .description = "Double a constrained integer.",
    .fields = &.{.{ .name = "value", .description = "Value to double.", .constraints = .{ .minimum = -100, .maximum = 100 }, .example_json = "4" }},
});

pub const WeatherInput = struct {
    location: []const u8,
    unit: ?Unit = null,
    options: WeatherOptions = .{},
};
fn weather(input: WeatherInput) void {
    std.mem.doNotOptimizeAway(input);
}
pub const Weather = blacksmith.Tool(weather, .{
    .name = "weather",
    .description = "Validate a nested weather request.",
    .fields = &.{
        .{ .name = "location", .description = "City and country.", .constraints = .{ .min_length = 1, .max_length = 120 }, .example_json = "\"Helsinki\"" },
        .{ .name = "unit", .description = "Temperature unit.", .default_json = "\"celsius\"" },
        .{ .name = "options.language", .description = "Optional response language.", .constraints = .{ .max_length = 16 } },
    },
});

pub const LookupResult = union(enum) {
    found: struct { id: u64, label: []const u8 },
    absent: void,
};
fn lookup(_: struct { id: u64 }) LookupResult {
    return .{ .found = .{ .id = 7, .label = "example" } };
}
pub const Lookup = blacksmith.Tool(lookup, .{
    .name = "lookup",
    .description = "Return a tagged lookup result.",
});

pub const RequestContext = struct { request_id: []const u8 };
fn audit(input: struct { message: []const u8 }, context: RequestContext) void {
    std.mem.doNotOptimizeAway(.{ input, context });
}
pub const Audit = blacksmith.Tool(audit, .{
    .name = "audit",
    .description = "Record a message with host-injected request context.",
});

fn guarded(input: struct { allowed: bool }) error{Denied}!void {
    if (!input.allowed) return error.Denied;
}
pub const Guarded = blacksmith.Tool(guarded, .{
    .name = "guarded",
    .description = "Demonstrate a declared tool error.",
    .errors = &.{.{ .zig_name = "Denied", .code = "denied", .safe_message = "operation denied" }},
});

fn ping(_: struct {}) void {}
pub const Ping = blacksmith.Tool(ping, .{
    .name = "ping",
    .description = "Return an explicit empty success.",
});

fn echo(input: struct { text: []const u8 }) []const u8 {
    return input.text;
}
pub const Echo = blacksmith.Tool(echo, .{
    .name = "echo",
    .description = "Echo bounded text.",
    .fields = &.{.{ .name = "text", .constraints = .{ .min_length = 1, .max_length = 256 } }},
});

fn matrix(input: struct { rows: []const []const i32 }) void {
    std.mem.doNotOptimizeAway(input);
}
pub const Matrix = blacksmith.Tool(matrix, .{
    .name = "matrix",
    .description = "Accept nested integer arrays.",
    .fields = &.{.{ .name = "rows", .constraints = .{ .min_items = 1, .max_items = 16 } }},
});

fn remove(input: struct { path: []const u8 }) void {
    std.mem.doNotOptimizeAway(input);
}
pub const Remove = blacksmith.Tool(remove, .{
    .name = "remove",
    .description = "Demonstrate destructive and idempotent safety hints.",
    .safety = .{ .destructive = true, .idempotent = true },
});

fn ratio(input: struct { numerator: f64, denominator: f64 }) f64 {
    return input.numerator / input.denominator;
}
pub const Ratio = blacksmith.Tool(ratio, .{
    .name = "ratio",
    .description = "Divide bounded floating point values.",
    .fields = &.{
        .{ .name = "numerator", .constraints = .{ .minimum = -1_000_000, .maximum = 1_000_000 } },
        .{ .name = "denominator", .constraints = .{ .minimum = 0.000001, .maximum = 1_000_000 } },
    },
});

pub const Registry = blacksmith.Registry(.{
    Scale,
    Weather,
    Lookup,
    Audit,
    Guarded,
    Ping,
    Echo,
    Matrix,
    Remove,
    Ratio,
});

pub fn main(init: std.process.Init) !void {
    var buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    defer stdout.interface.flush() catch {};
    try stdout.interface.print("{d} tools registered\n", .{Registry.all.len});
}
