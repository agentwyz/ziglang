const std = @import("std");
const builtin = @import("builtin");

pub const requires_symlinks = true;

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    add(b, test_step, .Debug);
    add(b, test_step, .ReleaseFast);
    add(b, test_step, .ReleaseSmall);
    add(b, test_step, .ReleaseSafe);
}

fn add(b: *std.Build, test_step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
    const target: std.zig.CrossTarget = .{ .os_tag = .macos };

    testUnwindInfo(b, test_step, optimize, target, false, "no-dead-strip");
    testUnwindInfo(b, test_step, optimize, target, true, "yes-dead-strip");
}

fn testUnwindInfo(
    b: *std.Build,
    test_step: *std.Build.Step,
    optimize: std.builtin.OptimizeMode,
    target: std.zig.CrossTarget,
    dead_strip: bool,
    name: []const u8,
) void {
    const exe = createScenario(b, optimize, target, name);
    exe.link_gc_sections = dead_strip;

    const check = exe.checkObject();
    check.checkInHeaders();
    check.checkExact("segname __TEXT");
    check.checkExact("sectname __gcc_except_tab");
    check.checkExact("sectname __unwind_info");

    switch (builtin.cpu.arch) {
        .aarch64 => {
            check.checkExact("sectname __eh_frame");
        },
        .x86_64 => {}, // We do not expect `__eh_frame` section on x86_64 in this case
        else => unreachable,
    }

    check.checkInSymtab();
    check.checkContains("(__TEXT,__text) private external ___gxx_personality_v0");
    test_step.dependOn(&check.step);

    const run = b.addRunArtifact(exe);
    run.skip_foreign_checks = true;
    run.expectStdOutEqual(
        \\Constructed: a
        \\Constructed: b
        \\About to destroy: b
        \\About to destroy: a
        \\Error: Not enough memory!
        \\
    );

    test_step.dependOn(&run.step);
}

fn createScenario(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.zig.CrossTarget,
    name: []const u8,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .optimize = optimize,
        .target = target,
    });
    b.default_step.dependOn(&exe.step);
    exe.addIncludePath(.{ .path = "." });
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "main.cpp",
            "simple_string.cpp",
            "simple_string_owner.cpp",
        },
    });
    exe.linkLibCpp();
    return exe;
}
