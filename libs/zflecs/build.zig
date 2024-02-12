const builtin = @import("builtin");
const std = @import("std");

pub const Package = struct {
    zflecs: *std.Build.Module,
    zflecs_c_cpp: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.root_module.addImport("zflecs", pkg.zflecs);
        exe.addIncludePath(.{ .path = thisDir() ++ "/libs/flecs" });
        exe.linkLibrary(pkg.zflecs_c_cpp);
    }
};

pub fn package(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    _: struct {},
) Package {
    const zflecs = b.addModule("zflecs", .{
        .root_source_file = .{ .path = thisDir() ++ "/src/zflecs.zig" },
    });

    const zflecs_c_cpp = b.addStaticLibrary(.{
        .name = "zflecs",
        .target = target,
        .optimize = optimize,
    });
    zflecs_c_cpp.linkLibC();
    zflecs_c_cpp.addIncludePath(.{ .path = thisDir() ++ "/libs/flecs" });
    zflecs_c_cpp.addCSourceFile(.{
        .file = .{ .path = thisDir() ++ "/libs/flecs/flecs.c" },
        .flags = &.{
            "-fno-sanitize=undefined",
            "-DFLECS_NO_CPP",
            "-DFLECS_USE_OS_ALLOC",
            if (builtin.mode == .Debug) "-DFLECS_SANITIZE" else "",
        },
    });

    switch (target.result.os.tag) {
        .windows => {
            zflecs_c_cpp.linkSystemLibrary("ws2_32");
        },
        .emscripten => {
            zflecs_c_cpp.defineCMacro("__EMSCRIPTEN__", "1");
            zflecs_c_cpp.addIncludePath(.{ .path = b.pathJoin(&.{ b.sysroot.?, "include" }) });
        },
        else => {},
    }

    return .{
        .zflecs = zflecs,
        .zflecs_c_cpp = zflecs_c_cpp,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run zflecs tests");
    test_step.dependOn(runTests(b, optimize, target));

    _ = package(b, target, optimize, .{});
}

pub fn runTests(
    b: *std.Build,
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
) *std.Build.Step {
    const tests = b.addTest(.{
        .name = "zflecs-tests",
        .root_source_file = .{ .path = thisDir() ++ "/src/zflecs.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zflecs_pkg = package(b, target, optimize, .{});
    zflecs_pkg.link(tests);

    return &b.addRunArtifact(tests).step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
