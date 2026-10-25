const std = @import("std");
const build_options = @import("build_options");

const usage =
    \\zig-tool locates the nearest Zig project and runs its project-bound
    \\`zig build blacksmith -- ...` backend. The search stops at a directory
    \\containing `.git` or at $HOME.
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

    const home = if (init.environ_map.get("HOME")) |path|
        std.Io.Dir.cwd().realPathFileAlloc(init.io, path, arena) catch null
    else
        null;
    const root_path = findProjectRoot(init.io, arena, home) catch {
        std.debug.print("zig-tool: no build.zig with build.zig.zon found in the current directory or its parents\n{s}", .{usage});
        std.process.exit(2);
    };
    std.debug.print("zig-tool: using project {s}\n", .{root_path});
    var root = try std.Io.Dir.cwd().openDir(init.io, root_path, .{});
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
        .signal => |signal| std.process.exit(signalStatus(signal)),
        else => std.process.exit(1),
    }
}

fn signalStatus(signal: anytype) u8 {
    if (@TypeOf(signal) == void) return 1;
    return 128 + @as(u8, @intCast(@min(@backingInt(signal), 127)));
}

fn findProjectRoot(io: std.Io, arena: std.mem.Allocator, home: ?[]const u8) ![]const u8 {
    var current: []const u8 = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", arena);
    while (true) {
        var dir = try std.Io.Dir.cwd().openDir(io, current, .{});
        defer dir.close(io);
        if (exists(io, dir, "build.zig") and exists(io, dir, "build.zig.zon")) return current;
        if (exists(io, dir, ".git")) break;
        if (home) |path| if (std.mem.eql(u8, current, path)) break;
        current = std.fs.path.dirname(current) orelse break;
    }
    return error.ProjectNotFound;
}

fn exists(io: std.Io, dir: std.Io.Dir, name: []const u8) bool {
    dir.access(io, name, .{}) catch return false;
    return true;
}
