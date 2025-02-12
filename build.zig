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
    const exe = addDependencies(b, b.addExecutable(.{
        .name = "circular",
        .root_source_file = b.path("./src/main.zig"),

        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}), 
    }));

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the project");
    run_step.dependOn(&run_exe.step);

    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    for (release_targets) |release_target| {
        const release_exe = addDependencies(b, b.addExecutable(.{
            .name = "circular",
            .root_source_file = b.path("./src/main.zig"),

            .target = b.resolveTargetQuery(release_target),
            .optimize = .ReleaseSafe,
        }));

        const release_output = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try release_target.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&release_output.step);
    }
}

// Add the dependencies.
pub fn addDependencies(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const target = exe.root_module.resolved_target orelse b.standardTargetOptions(.{});
    const optimize = exe.root_module.optimize orelse b.standardOptimizeOption(.{});

    const glfw = b.dependency("zglfw", .{ .target = target, .optimize = optimize });
    const opengl = b.dependency("zopengl", .{});

    if (b.lazyDependency("system_sdk", .{})) |sdk| {
        switch (target.result.os.tag) {
            .linux => {
                if (target.result.cpu.arch.isX86()) {
                    exe.addLibraryPath(sdk.path("linux/lib/x86_64-linux-gnu"));
                } else if (target.result.cpu.arch.isArm()) {
                    exe.addLibraryPath(sdk.path("linux/lib/x86_64-linux-gnu"));
                }
            },

            .macos => {
                exe.addLibraryPath(sdk.path("macos12/usr/lib"));
                exe.addFrameworkPath(sdk.path("macos12/System/Library/Frameworks"));
            },

            .windows => {
                if (target.result.cpu.arch.isX86() and (target.result.abi.isGnu() or target.result.abi.isMusl())) {
                    exe.addLibraryPath(sdk.path("windows/lib/x86_64-windows-gnu"));
                }
            },

            else => {}
        }
    }

    exe.root_module.addImport("glfw", glfw.module("root"));
    exe.root_module.addImport("gl", opengl.module("root"));
    exe.root_module.linkLibrary(glfw.artifact("glfw"));
 
    return exe;
}
