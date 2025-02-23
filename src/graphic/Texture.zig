const options = @import("options");
const std = @import("std");

const BasicTexture = if (options.backend_basic) @import("./backends/basic/Texture.zig") else struct {};
const OpenGLTexture = if (options.backend_basic) @import("./backends/opengl/Texture.zig") else struct {};

const Texture = @This();

allocator: std.mem.Allocator,
unmanaged: *anyopaque,

width: u16,
height: u16,

backend: Backend,
vtable: *const VTable,

// The vtable.
pub const VTable = struct {
    deinit: *const fn(ptr: *anyopaque) void
};

// Deinitialize the texture.
pub fn deinit(self: *Texture) void {
    self.vtable.deinit(self.unmanaged);

    switch (self.backend) {
        .Basic => self.allocator.destroy(@as(*BasicTexture, @ptrCast(@alignCast(self.unmanaged)))),
        .OpenGL => self.allocator.destroy(@as(*OpenGLTexture, @ptrCast(@alignCast(self.unmanaged))))
    }
}

// The backend.
pub const Backend = enum(u4) {
    Basic,
    OpenGL
};
