//! Compile typed Zig functions into strict tool contracts for model providers and MCP.

const std = @import("std");

pub const contract = @import("contract.zig");
pub const declaration = @import("declaration.zig");
pub const derive = @import("derive.zig");
pub const diagnostic = @import("diagnostic.zig");
pub const emit = @import("emit.zig");
pub const registry = @import("registry.zig");
pub const runtime = @import("runtime.zig");
pub const build_integration = @import("build_integration.zig");

pub const Tool = declaration.Tool;
pub const Registry = registry.Registry;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(contract);
    std.testing.refAllDecls(derive);
    std.testing.refAllDecls(diagnostic);
    std.testing.refAllDecls(emit);
    std.testing.refAllDecls(runtime);
}
