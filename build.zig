const std = @import("std");

const release_targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },

    // .{ .cpu_arch = .aarch64, .os_tag = .linux },
    // .{ .cpu_arch = .aarch64, .os_tag = .macos }
};

// Build the project.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the test executable.
    const test_exe = b.addExecutable(.{
        .name = "circular",
        .root_source_file = b.path("./src/main.zig"),

        .target = target,
        .optimize = optimize 
    });

    addOptions(b, test_exe.root_module);
    addDependencies(b, test_exe.root_module);

    const run_exe = b.addRunArtifact(test_exe);
    const run_step = b.step("run", "Run the project");
    run_step.dependOn(&run_exe.step);

    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    // Build the release executables.
    for (release_targets) |release_target| {
        const release_exe = b.addExecutable(.{
            .name = "circular",
            .root_source_file = b.path("./src/main.zig"),

            .target = b.resolveTargetQuery(release_target),
            .optimize = .ReleaseSafe,

            .strip = true
        });

        addOptions(b, release_exe.root_module);
        addDependencies(b, release_exe.root_module);

        const release_output = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try release_target.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&release_output.step);
    }

    // Build the module.
    const module = b.addModule("circular", .{
        .root_source_file = b.path("./src/main.zig"),

        .target = target,
        .optimize = optimize
    });

    addOptions(b, module);
    addDependencies(b, module);
}

// Add the options.
pub fn addOptions(b: *std.Build, module: *std.Build.Module) void {
    const options = b.addOptions();
    options.addOption(bool, "backend_basic", true);
    options.addOption(bool, "backend_opengl", true);

    module.addOptions("options", options);
}

// Add the dependencies.
pub fn addDependencies(b: *std.Build, module: *std.Build.Module) void {
    const target = module.resolved_target.?;
    const optimize = module.optimize.?;

    const stbi = b.dependency("zstbi", .{});
    const glfw = b.dependency("zglfw", .{ .target = target, .optimize = optimize });
    const opengl = b.dependency("zopengl", .{});

    if (b.lazyDependency("system_sdk", .{})) |sdk| {
        switch (target.result.os.tag) {
            .linux => {
                if (target.result.cpu.arch.isX86()) {
                    module.addLibraryPath(sdk.path("linux/lib/x86_64-linux-gnu"));
                } else if (target.result.cpu.arch.isArm()) {
                    module.addLibraryPath(sdk.path("linux/lib/x86_64-linux-gnu"));
                }
            },

            .macos => {
                module.addLibraryPath(sdk.path("macos12/usr/lib"));
                module.addFrameworkPath(sdk.path("macos12/System/Library/Frameworks"));
            },

            .windows => {
                if (target.result.cpu.arch.isX86() and (target.result.abi.isGnu() or target.result.abi.isMusl())) {
                    module.addLibraryPath(sdk.path("windows/lib/x86_64-windows-gnu"));
                }
            },

            else => {}
        }
    }

    module.addImport("stbi", stbi.module("root"));
    module.addImport("glfw", glfw.module("root"));
    module.addImport("gl", opengl.module("root"));
    module.linkLibrary(stbi.artifact("zstbi"));
    module.linkLibrary(glfw.artifact("glfw"));
}
