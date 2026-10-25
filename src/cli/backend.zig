const std = @import("std");
const blacksmith = @import("blacksmith");
const tool_registry = @import("tool_registry");
const build_options = @import("build_options");

const Registry = tool_registry.Registry;

const usage =
    \\usage: zig-tool COMMAND [OPTIONS]
    \\
    \\  schema TOOL
    \\  emit TOOL --target json-schema|openai|anthropic|gemini|mcp [--out PATH]
    \\  check TOOL|all [--target TARGET] [--generated PATH]
    \\  fixtures generate TOOL|all --ack-version 2026-07-28
    \\  version
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};

    if (args.len < 2) fail("missing command\n{s}", .{usage});
    const command = args[1];
    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        try stdout.interface.print("zig-tool {s}\n", .{build_options.version});
        return;
    }
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try stdout.interface.writeAll(usage);
        return;
    }
    if (std.mem.eql(u8, command, "schema")) return schema(arena, &stdout.interface, args);
    if (std.mem.eql(u8, command, "emit")) return emitCommand(init.io, arena, &stdout.interface, args);
    if (std.mem.eql(u8, command, "check")) return check(init.io, arena, &stdout.interface, args);
    if (std.mem.eql(u8, command, "fixtures")) return fixtures(init.io, arena, &stdout.interface, args);
    fail("unknown command: {s}\n{s}", .{ command, usage });
}

fn schema(arena: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len != 3) fail("schema requires exactly one tool name", .{});
    const rendered = try renderContract(arena, args[2]);
    defer arena.free(rendered);
    try stdout.writeAll(rendered);
    try stdout.writeAll("\n");
}

fn emitCommand(io: std.Io, arena: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len < 5) fail("emit requires TOOL and --target TARGET", .{});
    const tool_name = args[2];
    var target: ?blacksmith.emit.Target = null;
    var output_path: ?[]const u8 = null;
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--target")) {
            i += 1;
            if (i >= args.len) fail("--target requires a value", .{});
            target = blacksmith.emit.Target.parse(args[i]) orelse fail("unknown target: {s}", .{args[i]});
        } else if (std.mem.eql(u8, args[i], "--out")) {
            i += 1;
            if (i >= args.len) fail("--out requires a path", .{});
            output_path = args[i];
        } else fail("unknown option: {s}", .{args[i]});
    }
    const selected = target orelse fail("emit requires --target", .{});
    if (Registry.diagnose(tool_name, selected)) |failure| failDiagnostic(failure);
    const rendered = try renderTarget(arena, tool_name, selected);
    defer arena.free(rendered);
    if (output_path) |path| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = rendered });
    } else {
        try stdout.writeAll(rendered);
        try stdout.writeAll("\n");
    }
}

fn check(io: std.Io, arena: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) fail("check requires TOOL or all", .{});
    const name = args[2];
    var target: ?blacksmith.emit.Target = null;
    var generated: ?[]const u8 = null;
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--target")) {
            i += 1;
            if (i >= args.len) fail("--target requires a value", .{});
            target = blacksmith.emit.Target.parse(args[i]) orelse fail("unknown target: {s}", .{args[i]});
        } else if (std.mem.eql(u8, args[i], "--generated")) {
            i += 1;
            if (i >= args.len) fail("--generated requires a path", .{});
            generated = args[i];
        } else fail("unknown option: {s}", .{args[i]});
    }

    if (std.mem.eql(u8, name, "all")) {
        if (generated != null or target != null) fail("check all does not accept --target or --generated", .{});
        const clean = try Registry.checkAll(stdout);
        if (!clean) std.process.exit(1);
        try stdout.writeAll("{\"status\":\"ok\",\"tools\":\"all\"}\n");
        return;
    }
    if (!Registry.contains(name)) fail("unknown tool: {s}", .{name});
    if (generated != null and target == null) fail("--generated requires --target", .{});
    if (target) |selected| {
        if (Registry.diagnose(name, selected)) |failure| failDiagnostic(failure);
        const rendered = try renderTarget(arena, name, selected);
        defer arena.free(rendered);
        if (generated) |path| {
            const existing = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 * 1024 * 1024)) catch
                fail("cannot read generated file: {s}", .{path});
            if (!std.mem.eql(u8, existing, rendered)) {
                failDiagnostic(.{
                    .stage = .emission,
                    .code = .stale_generated_file,
                    .target = targetToDiagnostic(selected),
                    .path = path,
                    .message = "generated file is stale",
                });
            }
        }
    } else {
        inline for (@typeInfo(blacksmith.emit.Target).@"enum".field_names) |target_name| {
            const selected = @field(blacksmith.emit.Target, target_name);
            if (Registry.diagnose(name, selected)) |failure| failDiagnostic(failure);
            const rendered = try renderTarget(arena, name, selected);
            arena.free(rendered);
        }
    }
    try stdout.writeAll("{\"status\":\"ok\",\"tool\":");
    try std.json.Stringify.value(name, .{}, stdout);
    try stdout.writeAll("}\n");
}

fn fixtures(io: std.Io, arena: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len != 6 or !std.mem.eql(u8, args[2], "generate") or !std.mem.eql(u8, args[4], "--ack-version"))
        fail("fixtures generate requires TOOL|all --ack-version 2026-07-28", .{});
    if (!std.mem.eql(u8, args[5], blacksmith.contract.McpProtocolVersion))
        fail("fixture version acknowledgement must be {s}", .{blacksmith.contract.McpProtocolVersion});
    const name = args[3];
    if (std.mem.eql(u8, name, "all")) {
        inline for (Registry.all) |Tool| try writeFixturesFor(io, arena, Tool.meta.name);
    } else {
        if (!Registry.contains(name)) fail("unknown tool: {s}", .{name});
        try writeFixturesFor(io, arena, name);
    }
    try stdout.writeAll("{\"status\":\"generated\"}\n");
}

fn writeFixturesFor(io: std.Io, arena: std.mem.Allocator, name: []const u8) !void {
    inline for (@typeInfo(blacksmith.emit.Target).@"enum".field_names) |target_name| {
        const target = @field(blacksmith.emit.Target, target_name);
        if (Registry.diagnose(name, target) == null) {
            const rendered = try renderTarget(arena, name, target);
            defer arena.free(rendered);
            const path = try std.fmt.allocPrint(arena, "test/fixtures/generated/{s}.{s}.json", .{ name, target_name });
            defer arena.free(path);
            try std.Io.Dir.cwd().createDirPath(io, "test/fixtures/generated");
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = rendered });
        }
    }
}

fn renderContract(arena: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    defer out.deinit();
    if (!try Registry.writeContract(&out.writer, name)) fail("unknown tool: {s}", .{name});
    return out.toOwnedSlice();
}

fn renderTarget(arena: std.mem.Allocator, name: []const u8, target: blacksmith.emit.Target) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    defer out.deinit();
    if (!try Registry.writeTarget(&out.writer, name, target)) fail("unknown tool: {s}", .{name});
    return out.toOwnedSlice();
}

fn targetToDiagnostic(target: blacksmith.emit.Target) blacksmith.diagnostic.Target {
    return switch (target) {
        .json_schema => .json_schema,
        .openai => .openai,
        .anthropic => .anthropic,
        .gemini => .gemini,
        .mcp => .mcp,
    };
}

fn failDiagnostic(failure: blacksmith.diagnostic.Diagnostic) noreturn {
    std.debug.print("{f}\n", .{std.json.fmt(failure, .{})});
    std.process.exit(1);
}

fn fail(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print("zig-tool: " ++ format ++ "\n", args);
    std.process.exit(2);
}
