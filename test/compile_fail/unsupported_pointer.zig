const blacksmith = @import("blacksmith");

fn invalid(_: struct { pointer: *u32 }) void {}

const Invalid = blacksmith.Tool(invalid, .{
    .name = "invalid",
    .description = "This declaration must not compile.",
});

comptime {
    _ = Invalid.Input;
}
