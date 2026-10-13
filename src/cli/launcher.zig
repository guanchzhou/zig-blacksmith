const std = @import("std");
const build_options = @import("build_options");

const usage =
    \\zig-tool locates the nearest Zig project and runs its project-bound
    \\`zig build blacksmith -- ...` backend.
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "version"))) {
        var buffer: [128]u8 = undefined;
        var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
        defer stdout.interface.flush() catch {};
        try stdout.interface.print("zig-tool {s}\n", .{build_options.version});
        return;
    }

    const root = findProjectRoot(init.io) catch {
        std.debug.print("zig-tool: no build.zig found in the current directory or its parents\n{s}", .{usage});
        std.process.exit(2);
    };
    defer root.close(init.io);

    var child_args: std.ArrayList([]const u8) = .empty;
    defer child_args.deinit(arena);
    try child_args.appendSlice(arena, &.{ "zig", "build", "blacksmith", "--" });
    if (args.len > 1) try child_args.appendSlice(arena, args[1..]);

    var child = try std.process.spawn(init.io, .{
        .argv = child_args.items,
        .cwd = .{ .dir = root },
    });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| std.process.exit(code),
        else => std.process.exit(1),
    }
}

fn findProjectRoot(io: std.Io) !std.Io.Dir {
    var current = try std.Io.Dir.cwd().openDir(io, ".", .{});
    errdefer current.close(io);
    for (0..64) |_| {
        if (current.statFile(io, "build.zig", .{})) |_| return current else |_| {}
        const parent = try current.openDir(io, "..", .{});
        current.close(io);
        current = parent;
    }
    return error.ProjectNotFound;
}
