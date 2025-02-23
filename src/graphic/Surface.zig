const options = @import("options");
const std = @import("std");

const OpenGLSurface = if (options.backend_opengl) @import("./backends/opengl/Surface.zig") else struct {};
const BasicSurface = if (options.backend_basic) @import("./backends/basic/Surface.zig") else struct {};
const Texture = @import("./Texture.zig");
const Color = @import("./Color.zig");

const Surface = @This();

allocator: std.mem.Allocator,
unmanaged: *anyopaque,

width: u16,
height: u16,

backend: Backend,
vtable: *const VTable,

// The vtable.
pub const VTable = struct {
    deinit: *const fn(ptr: *anyopaque) void,

    clear: *const fn(ptr: *anyopaque) anyerror!void,
    fill: *const fn(ptr: *anyopaque, color: Color) anyerror!void,

    drawRectangle: *const fn (ptr: *anyopaque, color: Color, x: i17, y: i17, width: u16, height: u16) anyerror!void,
    drawTexture: *const fn(ptr: *anyopaque, texture: Texture, x: i17, y: i17, width: u16, height: u16) anyerror!void,
    
    read: *const fn(ptr: *anyopaque, format: Format, buffer: []u8) anyerror!void
};

// Initialize a surface.
pub fn init(backend: Backend, width: u16, height: u16, threads: u8, allocator: std.mem.Allocator) !Surface {
    switch (backend) {
        .Basic => { 
            if (!comptime options.backend_basic) {
                return error.BackendNotAvialiable;
            }

            const unmanaged = try allocator.create(BasicSurface);
            errdefer allocator.destroy(unmanaged);

            unmanaged.* = try BasicSurface.init(width, height, threads, allocator);

            return Surface{
                .allocator = allocator,
                .unmanaged = unmanaged,

                .width = width,
                .height = height,

                .backend = backend,
                .vtable = &BasicSurface.VTable
            };
        },

        .OpenGL => {
            if (!comptime options.backend_opengl) {
                return error.BackendNotAvialiable;
            }

            const unmanaged = try allocator.create(OpenGLSurface);
            errdefer allocator.destroy(unmanaged);

            unmanaged.* = try OpenGLSurface.init(width, height, allocator);

            return Surface{
                .allocator = allocator,
                .unmanaged = unmanaged,

                .width = width,
                .height = height,

                .backend = backend,
                .vtable = &OpenGLSurface.VTable
            };
        }
    }
}

// Deinitialize the surface.
pub fn deinit(self: *Surface) void {
    self.vtable.deinit(self.unmanaged);

    switch (self.backend) {
        .Basic => self.allocator.destroy(@as(*BasicSurface, @ptrCast(@alignCast(self.unmanaged)))),
        .OpenGL => self.allocator.destroy(@as(*OpenGLSurface, @ptrCast(@alignCast(self.unmanaged))))
    }
}

// Clear the surface.
pub fn clear(self: *Surface) !void {
    try self.vtable.clear(self.unmanaged);
}

// Fill the surface.
pub fn fill(self: *Surface, color: Color) !void {
    try self.vtable.fill(self.unmanaged, color);
}

// Draw a rectangle.
pub fn drawRectangle(self: *Surface, color: Color, x: i17, y: i17, width: u16, height: u16) !void {
    try self.vtable.drawRectangle(self.unmanaged, color, x, y, width, height);
}

// Draw a texture.
pub fn drawTexture(self: *Surface, texture: Texture, x: i17, y: i17, width: u16, height: u16) !void {
    try self.vtable.drawTexture(self.unmanaged, texture, x, y, width, height);
}

// Read the surface.
pub fn read(self: *Surface, format: Format, buffer: []u8) !void {
    try self.vtable.read(self.unmanaged, format, buffer);
}

// The backend.
pub const Backend = enum(u4) {
    Basic,
    OpenGL
};

// The pixel format.
pub const Format = enum(u4) {
    RGB,
    RGBA
};
