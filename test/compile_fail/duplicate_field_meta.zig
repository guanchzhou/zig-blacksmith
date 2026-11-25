const blacksmith = @import("blacksmith");

fn run(_: struct { count: i32 }) void {}

test {
    _ = blacksmith.Tool(run, .{
        .name = "dup_fields",
        .description = "Duplicate field metadata should fail at compile time.",
        .fields = &.{
            .{ .name = "count", .description = "First." },
            .{ .name = "count", .description = "Second." },
        },
    });
}
