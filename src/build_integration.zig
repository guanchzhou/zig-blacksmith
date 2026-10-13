//! Build helper for a project-bound CLI backend.

const std = @import("std");

pub const backend_import_name = "tool_registry";
pub const backend_source_path = "src/cli/backend.zig";
pub const build_step_name = "blacksmith";

pub const Options = struct {
    registry: *std.Build.Module,
    blacksmith: *std.Build.Module,
    backend_source: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    version: []const u8,
};

pub fn addToolCommands(b: *std.Build, options: Options) *std.Build.Step.Compile {
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", options.version);
    const backend = b.addExecutable(.{
        .name = "zig-tool-backend",
        .root_module = b.createModule(.{
            .root_source_file = options.backend_source,
            .target = options.target,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "blacksmith", .module = options.blacksmith },
                .{ .name = backend_import_name, .module = options.registry },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });
    b.installArtifact(backend);
    const run_backend = b.addRunArtifact(backend);
    run_backend.addPassthruArgs();
    b.step(build_step_name, "Run the project-bound zig-tool backend").dependOn(&run_backend.step);
    return backend;
}

pub fn validateRegistry(comptime Registry: type) void {
    _ = Registry.all;
    _ = Registry.contains;
    _ = Registry.writeContract;
    _ = Registry.writeTarget;
}
