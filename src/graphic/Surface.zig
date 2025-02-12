const std = @import("std");

const OpenGLSurface = @import("./backends/opengl/Surface.zig");
const BasicSurface = @import("./backends/basic/Surface.zig");
const Color = @import("./Color.zig");

const Surface = @This();

width: u16,
height: u16,

allocator: std.mem.Allocator,
backend: union(Backend) {
    Basic: BasicSurface,
    OpenGL: OpenGLSurface
},

// The backend.
pub const Backend = enum(u4) {
    Basic,
    OpenGL
};

// Initialize a surface.
pub fn init(backend: Backend, width: u16, height: u16, threads: u8, allocator: std.mem.Allocator) !Surface {
    return Surface{
        .width = width,
        .height = height,

        .allocator = allocator,
        .backend = switch (backend) {
            .Basic => .{ .Basic = try BasicSurface.init(width, height, threads, allocator) },
            .OpenGL => .{ .OpenGL = try OpenGLSurface.init(width, height) }
        }
    };
}

// Deinitialize the surface.
pub fn deinit(self: *Surface) void {
    switch (self.backend) {
        .Basic => |surface| @constCast(&surface).deinit(),
        .OpenGL => |surface| @constCast(&surface).deinit()
    }
}

// Clear the surface.
pub fn clear(self: *Surface) void {
    switch (self.backend) {
        .Basic => |surface| @constCast(&surface).clear(),
        .OpenGL => |surface| @constCast(&surface).clear()
    }
}

// Fill the surface.
pub fn fill(self: *Surface, color: Color) void {
    switch (self.backend) {
        .Basic => |surface| @constCast(&surface).fill(color),
        .OpenGL => |surface| @constCast(&surface).fill(color)
    }
}

// Read the surface.
pub fn read(self: *Surface, format: Format, buffer: []u8) !void {
    switch (self.backend) {
        .Basic => |surface| try @constCast(&surface).read(format, buffer),
        .OpenGL => |surface| try @constCast(&surface).read(format, buffer)
    }
}

// The pixel format.
pub const Format = enum(u4) {
    RGB,
    RGBA
};
