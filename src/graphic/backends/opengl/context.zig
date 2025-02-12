const glfw = @import("glfw");
const std = @import("std");
const gl = @import("gl");

var context = @as(?Window, null);
var dependcies = @as(usize, 0);

// Initialize the context.
pub fn init() !void {
    if (dependcies == 0) {
        try glfw.init(); 

        context = try Window.create(1, 1, "circular", .{ .visible = false });
        context.?.setCurrent();

        try gl.loadCoreProfile(glfw.getProcAddress, 4, 0);
    }

    dependcies += 1;
}

// Deinitialize the context.
pub fn deinit() void {
    dependcies -= 1;

    if (dependcies == 0) {
        context.?.destory();
        glfw.terminate();
    }
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
