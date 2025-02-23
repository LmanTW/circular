const gl = @import("gl").bindings;
const stbi = @import("stbi");
const std = @import("std");

const Texture = @import("../../Texture.zig");

const OpenGLTexture = @This();

allocator: std.mem.Allocator,
texture: gl.Uint,

width: u16,
height: u16,

// The vtable.
pub const VTable = Texture.VTable{
    .deinit = deinit
};

// Initialize a texture.
pub fn init(buffer: []u8, allocator: std.mem.Allocator) !OpenGLTexture {
    stbi.init(allocator);
    defer stbi.deinit();

    var image = try stbi.Image.loadFromMemory(buffer, 4);
    defer image.deinit();

    var texture = @as(gl.Uint, undefined);

    gl.genTextures(1, @as([*]gl.Uint, @ptrCast(&texture)));
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @as(gl.Sizei, @intCast(image.width)), @as(gl.Sizei, @intCast(image.height)), 0, gl.RGBA, gl.UNSIGNED_BYTE, @as(*anyopaque, @ptrCast(image.data)));
    gl.bindTexture(gl.TEXTURE_2D, 0);

    return OpenGLTexture{
        .allocator = allocator,
        .texture = texture,

        .width = @as(u16, @intCast(image.width)),
        .height = @as(u16, @intCast(image.height)),
    };
}

// Deinitialize the texture.
pub fn deinit(ptr: *anyopaque) void {
    const self = @as(*OpenGLTexture, @ptrCast(@alignCast(ptr)));

    gl.deleteFramebuffers(1, @as([*]gl.Uint, @ptrCast(&self.texture)));
}
