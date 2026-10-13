const blacksmith = @import("blacksmith");

fn first(_: struct {}) void {}
fn second(_: struct {}) void {}

const First = blacksmith.Tool(first, .{ .name = "duplicate", .description = "First." });
const Second = blacksmith.Tool(second, .{ .name = "duplicate", .description = "Second." });

pub const Broken = blacksmith.Registry(.{ First, Second });

comptime {
    _ = Broken;
}
