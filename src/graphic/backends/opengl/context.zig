const glfw = @import("glfw");
const opengl = @import("gl");
const std = @import("std");
const gl = opengl.bindings;

var context = @as(?Window, null);
var dependcies = @as(usize, 0);

pub var texture_program = @as(gl.Uint, undefined);
pub var fill_program = @as(gl.Uint, undefined);

// Initialize the context.
pub fn init() !void {
    if (dependcies == 0) {
        try glfw.init(); 

        glfw.windowHint(glfw.WindowHint.context_version_major, 3);
        glfw.windowHint(glfw.WindowHint.context_version_minor, 3);
        glfw.windowHint(glfw.WindowHint.opengl_forward_compat, true);

        context = try Window.create(1, 1, "circular", .{ .visible = false });
        context.?.setCurrent();

        try opengl.loadCoreProfile(glfw.getProcAddress, 4, 0);

        texture_program = try createProgram(@embedFile("./shaders/texture.vertex"), @embedFile("./shaders/texture.fragment"));
        fill_program = try createProgram(@embedFile("./shaders/fill.vertex"), @embedFile("./shaders/fill.fragment"));
    }

    dependcies += 1;
}

// Deinitialize the context.
pub fn deinit() void {
    dependcies -= 1;

    if (dependcies == 0) {
        gl.deleteProgram(texture_program);
        gl.deleteProgram(fill_program);

        context.?.destory();
        glfw.terminate();

    }
}

// Create a program.
fn createProgram(vertex_shader_source: []const u8, fragment_shader_source: []const u8) !gl.Uint {
    const vertex_shader = try compileShader(gl.VERTEX_SHADER, vertex_shader_source);
    defer gl.deleteShader(vertex_shader);

    const fragment_shader = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_source);
    defer gl.deleteShader(fragment_shader);

    const program = gl.createProgram();

    gl.attachShader(program, vertex_shader);
    gl.attachShader(program, fragment_shader);
    gl.linkProgram(program);

    return program;
}

// Compile a shader.
fn compileShader(kind: comptime_int, source: []const u8) !gl.Uint {
    const shader = gl.createShader(kind);

    gl.shaderSource(shader, 1, @as([*c]const [*c]const gl.Char, @ptrCast(&source)), 0);
    gl.compileShader(shader);

    var status = @as(gl.Int, undefined);
    gl.getShaderiv(shader, gl.COMPILE_STATUS, &status);

    if (status != 1) {
        var log_length: gl.Int = 0;
        gl.getShaderiv(shader, gl.INFO_LOG_LENGTH, &log_length);

        if (log_length > 0) {
            var buffer = @as([1024]u8, undefined);
            var bytes_read: gl.Int = 0;

            gl.getShaderInfoLog(shader, buffer.len, &bytes_read, &buffer);

            _ = try std.io.getStdOut().write(buffer[0..@as(usize, @intCast(bytes_read))]);
        }

        return error.CompilationFailed;
    }

    return shader;
}

/// The window.
pub const Window = struct {
    native: *anyopaque,

    // The flags.
    pub const Flags = struct {
        visible: bool = true 
    };

    // Create a window.
    pub fn create(width: c_int, height: c_int, title: [:0]const u8, flags: Window.Flags) !Window {
        glfw.windowHint(glfw.WindowHint.visible, flags.visible);

        return Window{
            .native = try glfw.Window.create(width, height, title, null)
        };
    }

    // Destory the window.
    pub fn destory(self: *Window) void {
        glfw.Window.destroy(@as(*glfw.Window, @ptrCast(self.native)));
    }

    // Set the window as the current context.
    pub fn setCurrent(self: *Window) void {
        glfw.makeContextCurrent(@as(*glfw.Window, @ptrCast(self.native)));
    }
};
