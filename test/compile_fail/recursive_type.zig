const blacksmith = @import("blacksmith");

const Node = struct {
    next: ?[]const Node = null,
};

fn run(_: struct { root: Node }) void {}

test {
    _ = blacksmith.Tool(run, .{
        .name = "recursive",
        .description = "Recursive type should fail at compile time.",
    });
}
