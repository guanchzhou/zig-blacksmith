const blacksmith = @import("blacksmith");

fn handler(_: struct { value: i32 }) void {}

pub const Broken = blacksmith.Tool(handler, .{
    .name = "broken",
    .description = "Invalid metadata path fixture.",
    .fields = &.{.{ .name = "missing" }},
});

comptime {
    _ = Broken;
}
