const blacksmith = @import("blacksmith");

fn handler(_: struct { value: i32 }) void {}

pub const Broken = blacksmith.Tool(handler, .{
    .name = "broken",
    .description = "Constraint kind mismatch fixture.",
    .fields = &.{.{ .name = "value", .constraints = .{ .max_length = 4 } }},
});

comptime {
    _ = Broken;
}
