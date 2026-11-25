const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const blacksmith = b.addModule("blacksmith", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);

    const launcher = b.addExecutable(.{
        .name = "zig-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/launcher.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
        }),
    });
    b.installArtifact(launcher);

    const registry = b.createModule(.{
        .root_source_file = b.path("examples/tool_registry.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    });
    const backend = b.addExecutable(.{
        .name = "zig-tool-backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/backend.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "blacksmith", .module = blacksmith },
                .{ .name = "tool_registry", .module = registry },
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });
    b.installArtifact(backend);

    const run_backend = b.addRunArtifact(backend);
    run_backend.addPassthruArgs();
    b.step("blacksmith", "Run the project-bound zig-tool backend").dependOn(&run_backend.step);

    const test_step = b.step("test", "Run the complete test suite");
    const unit = b.addTest(.{ .root_module = blacksmith });
    test_step.dependOn(&b.addRunArtifact(unit).step);

    const launcher_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/cli/launcher.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
    }) });
    test_step.dependOn(&b.addRunArtifact(launcher_test).step);

    const integration = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blacksmith", .module = blacksmith },
            .{ .name = "tool_registry", .module = registry },
        },
    }) });
    test_step.dependOn(&b.addRunArtifact(integration).step);

    const fuzz_smoke = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "tool_registry", .module = registry }},
    }) });
    const run_fuzz_smoke = b.addRunArtifact(fuzz_smoke);
    test_step.dependOn(&run_fuzz_smoke.step);
    b.step("fuzz-smoke", "Run deterministic untrusted JSON fuzz smoke").dependOn(&run_fuzz_smoke.step);

    const spike = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("spikes/contracts.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "tool_registry", .module = registry }},
    }) });
    test_step.dependOn(&b.addRunArtifact(spike).step);

    const unsupported_pointer = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/unsupported_pointer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    unsupported_pointer.expect_errors = .{ .contains = "blacksmith does not support non-slice pointer fields" };
    test_step.dependOn(&unsupported_pointer.step);

    const invalid_metadata_path = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/invalid_metadata_path.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    invalid_metadata_path.expect_errors = .{ .contains = "blacksmith field metadata names a field path that does not exist" };
    test_step.dependOn(&invalid_metadata_path.step);

    const duplicate_registry_name = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/duplicate_registry_name.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    duplicate_registry_name.expect_errors = .{ .contains = "blacksmith registry contains duplicate tool names" };
    test_step.dependOn(&duplicate_registry_name.step);

    const non_finite_bound = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/non_finite_bound.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    non_finite_bound.expect_errors = .{ .contains = "blacksmith field maximum must be finite" };
    test_step.dependOn(&non_finite_bound.step);

    const constraint_kind_mismatch = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/constraint_kind_mismatch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    constraint_kind_mismatch.expect_errors = .{ .contains = "blacksmith length and item constraints apply only to strings and arrays" };
    test_step.dependOn(&constraint_kind_mismatch.step);

    const recursive_type = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/recursive_type.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    recursive_type.expect_errors = .{ .contains = "blacksmith does not support recursive types" };
    test_step.dependOn(&recursive_type.step);

    const duplicate_field_meta = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/duplicate_field_meta.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    duplicate_field_meta.expect_errors = .{ .contains = "blacksmith field metadata contains duplicate field paths" };
    test_step.dependOn(&duplicate_field_meta.step);

    const duplicate_declared_error = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/duplicate_declared_error.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "blacksmith", .module = blacksmith }},
    }) });
    duplicate_declared_error.expect_errors = .{ .contains = "blacksmith declared errors contain duplicate entries" };
    test_step.dependOn(&duplicate_declared_error.step);

    const example = b.addExecutable(.{
        .name = "weather-tools",
        .root_module = registry,
    });
    const run_example = b.addRunArtifact(example);
    run_example.expectExitCode(0);
    test_step.dependOn(&run_example.step);

    const docs = b.addInstallDirectory(.{
        .source_dir = unit.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Write API documentation to zig-out/docs").dependOn(&docs.step);

    const bench = b.addExecutable(.{
        .name = "blacksmith-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "blacksmith", .module = blacksmith },
                .{ .name = "tool_registry", .module = registry },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    b.step("bench", "Run schema and dispatch benchmarks").dependOn(&run_bench.step);
}
