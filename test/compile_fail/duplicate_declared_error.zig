const blacksmith = @import("blacksmith");

fn run(_: struct {}) error{Denied}!void {
    return error.Denied;
}

test {
    _ = blacksmith.Tool(run, .{
        .name = "dup_errors",
        .description = "Duplicate error metadata should fail at compile time.",
        .errors = &.{
            .{ .zig_name = "Denied", .code = "denied", .safe_message = "denied" },
            .{ .zig_name = "Other", .code = "denied", .safe_message = "other" },
        },
    });
}
