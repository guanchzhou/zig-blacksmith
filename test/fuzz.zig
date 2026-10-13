const std = @import("std");
const tools = @import("tool_registry");

fn exercise(input: []const u8) !void {
    const result = try tools.Scale.invoke(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "SECRET") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, result, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "untrusted JSON fuzz smoke" {
    const corpus = [_][]const u8{
        "",
        "{",
        "{\"value\":",
        "{\"value\":1,\"value\":2}",
        "{\"value\":\"SECRET\"}",
        "{\"value\":\"\\uD800\"}",
        "[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]",
        "{\"value\":-2147483649}",
        "{\"value\":2147483648}",
    };
    for (corpus) |input| try exercise(input);

    var state: u64 = 0x9e3779b97f4a7c15;
    var bytes: [256]u8 = undefined;
    for (0..512) |_| {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        const length: usize = @intCast(state % bytes.len);
        for (bytes[0..length], 0..) |*byte, i| {
            state = state *% 6364136223846793005 +% 1 +% @as(u64, @intCast(i));
            byte.* = @truncate(state);
        }
        try exercise(bytes[0..length]);
    }
}
