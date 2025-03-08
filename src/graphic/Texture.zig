const options = @import("options");
const std = @import("std");

const BasicTexture = if (options.backend_basic) @import("./backends/basic/Texture.zig") else struct {};
const OpenGLTexture = if (options.backend_basic) @import("./backends/opengl/Texture.zig") else struct {};
const Surface = @import("./Surface.zig");

const Texture = @This();

allocator: std.mem.Allocator,
unmanaged: *anyopaque,

width: u16,
height: u16,

backend: Surface.Backend,
vtable: *const VTable,

// The vtable.
pub const VTable = struct {
    deinit: *const fn(ptr: *anyopaque) void
};

// The style for the texture.
pub const Style = struct {
    flip_horizontal: bool = false,
    flip_vertical: bool = false
};

// Initialize a texture.
pub fn init(backend: Surface.Backend, buffer: []u8, style: Style, allocator: std.mem.Allocator) !Texture {
    switch (backend) {
        .Basic => {
            if (!comptime options.backend_basic) {
                return error.BackendNotAvialiable;
            }

            const unmanaged = try allocator.create(BasicTexture);
            errdefer allocator.destroy(unmanaged);

            unmanaged.* = try BasicTexture.init(buffer, style, allocator);

            return Texture{
                .allocator = allocator,
                .unmanaged = unmanaged,

                .width = unmanaged.width,
                .height = unmanaged.height,

                .backend = backend,
                .vtable = &BasicTexture.VTable
            };
        },

        .OpenGL => {
            if (!comptime options.backend_opengl) {
                return error.OpenGLNotAvialiable;
            }

            const unmanaged = try allocator.create(OpenGLTexture);
            errdefer allocator.destroy(unmanaged);

            unmanaged.* = try OpenGLTexture.init(buffer, style, allocator);

            return Texture{
                .allocator = allocator,
                .unmanaged = unmanaged,

                .width = unmanaged.width,
                .height = unmanaged.height,

                .backend = backend,
                .vtable = &OpenGLTexture.VTable
            };
        }
    }
}

// Deinitialize the texture.
pub fn deinit(self: *Texture) void {
    self.vtable.deinit(self.unmanaged);

    switch (self.backend) {
        .Basic => self.allocator.destroy(@as(*BasicTexture, @ptrCast(@alignCast(self.unmanaged)))),
        .OpenGL => self.allocator.destroy(@as(*OpenGLTexture, @ptrCast(@alignCast(self.unmanaged))))
    }
}
