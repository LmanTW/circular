const gl = @import("gl").bindings;
const std = @import("std");

const Surface = @import("../../Surface.zig");
const Color = @import("../../Color.zig");
const context = @import("./context.zig");

const OpenGLSurface = @This();

width: u16,
height: u16,

buffer: gl.Uint,
texture: gl.Uint,

// Initialize a surface.
pub fn init(width: u16, height: u16) !OpenGLSurface {
    try context.init();

    var buffer = @as(gl.Uint, undefined);
    var texture = @as(gl.Uint, undefined);

    gl.genFramebuffers(1, @as([*]gl.Uint, @ptrCast(&buffer)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, buffer);
    gl.genTextures(1, @as([*]gl.Uint, @ptrCast(&texture)));
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @as(gl.Sizei, @intCast(width)), @as(gl.Sizei, @intCast(height)), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);

    return OpenGLSurface{
        .width = width,
        .height = height,

        .buffer = buffer,
        .texture = texture
    };
}

// Deinitialize the surface.
pub fn deinit(self: *OpenGLSurface) void {
    gl.deleteFramebuffers(1, @as([*]c_uint, @ptrCast(&self.buffer)));
    gl.deleteTextures(1, @as([*]c_uint, @ptrCast(&self.texture)));

    context.deinit();
}

// Clear the surface.
pub fn clear(self: *OpenGLSurface) void {
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
}

// Fill the surface.
pub fn fill(self: *OpenGLSurface, color: Color) void {
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.clearColor(
        @as(gl.Float, @floatFromInt(color.r)) / 255,
        @as(gl.Float, @floatFromInt(color.g)) / 255,
        @as(gl.Float, @floatFromInt(color.b)) / 255,
        @as(gl.Float, @floatCast(color.a))
    );
    gl.clear(gl.COLOR_BUFFER_BIT);
}

// Read the surface.
pub fn read(self: *OpenGLSurface, format: Surface.Format, buffer: []u8) !void {
    const length = switch (format) {
        .RGB => (@as(u64, @intCast(self.width)) * self.height) * 3,
        .RGBA => (@as(u64, @intCast(self.width)) * self.height) * 4        
    };

    if (buffer.len != length) {
        return error.InvalidBufferLength;
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.readPixels(0, 0, @as(gl.Sizei, @intCast(self.width)), @as(gl.Sizei, @intCast(self.height)), switch (format) {
        .RGB => gl.RGB,
        .RGBA => gl.RGBA
    }, gl.UNSIGNED_BYTE, @as(*anyopaque, buffer.ptr));
}
