const std = @import("std");
const tools = @import("tool_registry");

pub const declarations = .{
    tools.Scale,
    tools.Weather,
    tools.Lookup,
    tools.Audit,
    tools.Guarded,
    tools.Ping,
    tools.Echo,
    tools.Matrix,
    tools.Remove,
    tools.Ratio,
};

test "compatibility corpus contains ten representative declarations" {
    try std.testing.expectEqual(@as(usize, 10), declarations.len);
}
