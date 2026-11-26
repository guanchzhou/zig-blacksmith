const builtin = @import("builtin");
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

const DirSecurityInfo = struct {
    dev: u64,
    uid: u32,
    mode: u32,
};

fn isTrustedDir(info: DirSecurityInfo, euid: u32, expected_dev: u64) bool {
    if (info.dev != expected_dev) return false;
    if (info.uid != euid) return false;
    if ((info.mode & 0o1002) != 0) return false;
    return true;
}

fn dirSecurityInfo(dir: std.Io.Dir) ?DirSecurityInfo {
    switch (builtin.os.tag) {
        .windows, .wasi => return null,
        .linux => {
            const linux = std.os.linux;
            var st = std.mem.zeroes(linux.Statx);
            const rc = linux.statx(dir.handle, "", linux.AT.EMPTY_PATH, linux.STATX.BASIC_STATS, &st);
            if (linux.errno(rc) != .SUCCESS) return null;
            return .{
                .dev = (@as(u64, st.dev_major) << 32) | st.dev_minor,
                .uid = st.uid,
                .mode = st.mode,
            };
        },
        else => {
            if (std.posix.Stat == void) return null;
            var st = std.mem.zeroes(std.posix.Stat);
            const fstat_sym = if (std.posix.lfs64_abi) std.posix.system.fstat64 else std.posix.system.fstat;
            if (std.posix.errno(fstat_sym(dir.handle, &st)) != .SUCCESS) return null;
            return .{
                .dev = @intCast(st.dev),
                .uid = @intCast(st.uid),
                .mode = @intCast(st.mode),
            };
        },
    }
}

fn currentEuid() ?u32 {
    return switch (builtin.os.tag) {
        .windows, .wasi => null,
        .linux => std.os.linux.geteuid(),
        else => @intCast(std.c.geteuid()),
    };
}

fn findProjectRoot(io: std.Io, arena: std.mem.Allocator, home: ?[]const u8) ![]const u8 {
    const start: []const u8 = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", arena);
    return findProjectRootFrom(io, start, home);
}

fn findProjectRootFrom(io: std.Io, start: []const u8, home: ?[]const u8) ![]const u8 {
    const euid = currentEuid();
    var start_dev: ?u64 = null;
    var current: []const u8 = start;
    while (true) {
        var dir = try std.Io.Dir.cwd().openDir(io, current, .{});
        defer dir.close(io);
        if (euid) |uid| {
            const info = dirSecurityInfo(dir) orelse break;
            if (start_dev == null) start_dev = info.dev;
            if (!isTrustedDir(info, uid, start_dev.?)) break;
        }
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

test "isTrustedDir enforces ownership, mode, and mount boundaries" {
    try std.testing.expect(isTrustedDir(.{ .dev = 1, .uid = 500, .mode = 0o40755 }, 500, 1));
    try std.testing.expect(!isTrustedDir(.{ .dev = 2, .uid = 500, .mode = 0o40755 }, 500, 1));
    try std.testing.expect(!isTrustedDir(.{ .dev = 1, .uid = 0, .mode = 0o40755 }, 500, 1));
    try std.testing.expect(!isTrustedDir(.{ .dev = 1, .uid = 500, .mode = 0o40777 }, 500, 1));
    try std.testing.expect(!isTrustedDir(.{ .dev = 1, .uid = 500, .mode = 0o41755 }, 500, 1));
    try std.testing.expect(!isTrustedDir(.{ .dev = 1, .uid = 500, .mode = 0o41777 }, 500, 1));
}

test "findProjectRootFrom refuses world-writable and sticky directories on POSIX" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "good/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "good/build.zig", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "good/build.zig.zon", .data = "" });

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const good_root = try tmp.dir.realPathFileAlloc(io, "good", arena);
    const good_sub = try tmp.dir.realPathFileAlloc(io, "good/sub", arena);
    const found = try findProjectRootFrom(io, good_sub, null);
    try std.testing.expectEqualStrings(good_root, found);

    // World-writable project directory must be refused.
    try tmp.dir.createDirPath(io, "writable/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "writable/build.zig", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "writable/build.zig.zon", .data = "" });
    var writable_dir = try tmp.dir.openDir(io, "writable", .{ .iterate = true });
    defer writable_dir.close(io);
    try writable_dir.setPermissions(io, .fromMode(0o777));
    defer writable_dir.setPermissions(io, .fromMode(0o755)) catch {};
    const writable_sub = try tmp.dir.realPathFileAlloc(io, "writable/sub", arena);
    try std.testing.expectError(error.ProjectNotFound, findProjectRootFrom(io, writable_sub, null));

    // Sticky project directory must be refused.
    try tmp.dir.createDirPath(io, "sticky/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "sticky/build.zig", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "sticky/build.zig.zon", .data = "" });
    var sticky_dir = try tmp.dir.openDir(io, "sticky", .{ .iterate = true });
    defer sticky_dir.close(io);
    try sticky_dir.setPermissions(io, .fromMode(0o1755));
    defer sticky_dir.setPermissions(io, .fromMode(0o755)) catch {};
    const sticky_sub = try tmp.dir.realPathFileAlloc(io, "sticky/sub", arena);
    try std.testing.expectError(error.ProjectNotFound, findProjectRootFrom(io, sticky_sub, null));
}
