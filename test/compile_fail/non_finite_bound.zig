const std = @import("std");
const blacksmith = @import("blacksmith");

fn handler(_: struct { value: f64 }) void {}

pub const Broken = blacksmith.Tool(handler, .{
    .name = "broken",
    .description = "Non-finite bound fixture.",
    .fields = &.{.{ .name = "value", .constraints = .{ .maximum = std.math.inf(f64) } }},
});

comptime {
    _ = Broken;
}
