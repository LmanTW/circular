const gl = @import("gl").bindings;
const std = @import("std");

const OpenGLTexture = @import("./Texture.zig");
const Surface = @import("../../Surface.zig");
const Texture = @import("../../Texture.zig");
const Color = @import("../../Color.zig");
const context = @import("./context.zig");

const OpenGLSurface = @This();

allocator: std.mem.Allocator,

width: u16,
height: u16,

buffer: gl.Uint,
texture: gl.Uint,

vertex_array: gl.Uint,
vertex_buffer: gl.Uint,
index_buffer: gl.Uint,

// The vtable.
pub const VTable = Surface.VTable{
    .deinit = deinit,

    .clear = clear,
    .fill = fill,

    .drawRectangle = drawRectangle,
    .drawTexture = drawTexture,

    .read = read
};

// Initialize a surface.
pub fn init(width: u16, height: u16, allocator: std.mem.Allocator) !OpenGLSurface {
    try context.init();

    var buffer = @as(gl.Uint, undefined);
    var texture = @as(gl.Uint, undefined);

    gl.genTextures(1, @as([*]gl.Uint, @ptrCast(&texture)));
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @as(gl.Sizei, @intCast(width)), @as(gl.Sizei, @intCast(height)), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.bindTexture(gl.TEXTURE_2D, 0);

    gl.genFramebuffers(1, @as([*]gl.Uint, @ptrCast(&buffer)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, buffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    gl.bindFramebuffer(gl.FRAMEBUFFER, 0);

    var vertex_array = @as(gl.Uint, undefined);
    var vertext_buffer = @as(gl.Uint, undefined);
    var index_buffer = @as(gl.Uint, undefined);

    gl.genVertexArrays(1, @as([*]gl.Uint, @ptrCast(&vertex_array)));
    gl.bindVertexArray(vertex_array);
    gl.genBuffers(1, @as([*]gl.Uint, @ptrCast(&vertext_buffer)));
    gl.bindBuffer(gl.ARRAY_BUFFER, vertext_buffer);

    gl.bufferData(gl.ARRAY_BUFFER, 24 * @sizeOf(gl.Float), null, gl.DYNAMIC_DRAW);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(gl.Float), null);
    gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(gl.Float), @ptrFromInt((2 * @sizeOf(gl.Float))));
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);

    gl.genBuffers(1, @as([*]gl.Uint, @ptrCast(&index_buffer)));
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, index_buffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * @sizeOf(gl.Float), &[_]gl.Float{0, 1, 2, 2, 3, 0}, gl.STATIC_DRAW);

    return OpenGLSurface{
        .allocator = allocator,

        .width = width,
        .height = height,

        .buffer = buffer,
        .texture = texture,

        .vertex_array = vertex_array,
        .vertex_buffer = vertext_buffer,
        .index_buffer = index_buffer
    };
}

// Deinitialize the surface.
pub fn deinit(ptr: *anyopaque) void {
    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

    gl.deleteFramebuffers(1, @as([*]gl.Uint, @ptrCast(&self.buffer)));
    gl.deleteTextures(1, @as([*]gl.Uint, @ptrCast(&self.texture)));
    gl.deleteVertexArrays(1, @as([*]gl.Uint, @ptrCast(&self.vertex_array)));
    gl.deleteBuffers(1, @as([*]gl.Uint, @ptrCast(&self.vertex_buffer)));
    gl.deleteBuffers(1, @as([*]gl.Uint, @ptrCast(&self.index_buffer)));

    context.deinit();
}

// Clear the surface.
pub fn clear(ptr: *anyopaque) !void {
    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer); 
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
}

// Fill the surface.
pub fn fill(ptr: *anyopaque, color: Color) !void {
    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

    gl.viewport(0, 0, @as(gl.Sizei, @intCast(self.width)), @as(gl.Sizei, @intCast(self.height)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.clearColor(
        @as(gl.Float, @floatFromInt(color.r)) / 255,
        @as(gl.Float, @floatFromInt(color.g)) / 255,
        @as(gl.Float, @floatFromInt(color.b)) / 255,
        @as(gl.Float, @floatCast(color.a))
    );
    gl.clear(gl.COLOR_BUFFER_BIT);
}

// Draw a rectangle.
pub fn drawRectangle(ptr: *anyopaque, color: Color, x: i17, y: i17, width: u16, height: u16) !void {
    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

    const width_scale = @as(f32, @floatFromInt(self.width)) / 2;
    const height_scale = @as(f32, @floatFromInt(self.height)) / 2;
    const start_x = (@as(gl.Float, @floatFromInt(x)) / width_scale) - 1;
    const start_y = (@as(gl.Float, @floatFromInt(y)) / height_scale) - 1;
    const end_x = start_x + (@as(gl.Float, @floatFromInt(width)) / width_scale);
    const end_y = start_y + (@as(gl.Float, @floatFromInt(height)) / height_scale);

    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    defer gl.bindBuffer(gl.ARRAY_BUFFER, 0);

    gl.bufferSubData(gl.ARRAY_BUFFER, 0, 24 * @sizeOf(gl.Float), &[_]gl.Float{
        start_x, start_y, 0.0, 0.0,
        start_x, end_y,   0.0, 1.0,
        end_x,   start_y, 1.0, 0.0,

        start_x, end_y,   0.0, 1.0,
        end_x,   start_y, 1.0, 0.0,
        end_x,   end_y,   1.0, 1.0,
    });

    gl.viewport(0, 0, @as(gl.Sizei, @intCast(self.width)), @as(gl.Sizei, @intCast(self.height)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.bindVertexArray(self.vertex_array);
    gl.useProgram(context.fill_program); 
    gl.uniform4f(
        gl.getUniformLocation(context.fill_program, "uColor"),
        @as(gl.Float, @floatFromInt(color.r)) / 255,
        @as(gl.Float, @floatFromInt(color.g)) / 255,
        @as(gl.Float, @floatFromInt(color.b)) / 255,
        std.math.clamp(color.a, 0, 1)
    ); 
    gl.drawArrays(gl.TRIANGLES, 0, 6);
}

// Draw a texture.
pub fn drawTexture(ptr: *anyopaque, texture: Texture, x: i17, y: i17, width: u16, height: u16) !void {
    if (texture.backend != .OpenGL) {
        return error.BackendMismatch;
    }

    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

    const width_scale = @as(f32, @floatFromInt(self.width)) / 2;
    const height_scale = @as(f32, @floatFromInt(self.height)) / 2;
    const start_x = (@as(gl.Float, @floatFromInt(x)) / width_scale) - 1;
    const start_y = (@as(gl.Float, @floatFromInt(y)) / height_scale) - 1;
    const end_x = start_x + (@as(gl.Float, @floatFromInt(width)) / width_scale);
    const end_y = start_y + (@as(gl.Float, @floatFromInt(height)) / height_scale);

    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    defer gl.bindBuffer(gl.ARRAY_BUFFER, 0);

    gl.bufferSubData(gl.ARRAY_BUFFER, 0, 24 * @sizeOf(gl.Float), &[_]gl.Float{
        start_x, start_y, 0.0, 0.0,
        start_x, end_y,   0.0, 1.0,
        end_x,   start_y, 1.0, 0.0,

        start_x, end_y,   0.0, 1.0,
        end_x,   start_y, 1.0, 0.0,
        end_x,   end_y,   1.0, 1.0,
    });

    const managed_texture = @as(*OpenGLTexture, @ptrCast(@alignCast(texture.unmanaged)));

    gl.viewport(0, 0, @as(gl.Sizei, @intCast(self.width)), @as(gl.Sizei, @intCast(self.height)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.buffer);
    gl.bindVertexArray(self.vertex_array);
    gl.useProgram(context.texture_program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, managed_texture.texture);
    gl.uniform1i(gl.getUniformLocation(context.texture_program, "flipHorizontal"), @intFromBool(managed_texture.style.flip_horizontal));
    gl.uniform1i(gl.getUniformLocation(context.texture_program, "flipVertical"), @intFromBool(managed_texture.style.flip_vertical));
    gl.drawArrays(gl.TRIANGLES, 0, 6);
}

// Read the surface.
pub fn read(ptr: *anyopaque, format: Surface.Format, buffer: []u8) !void {
    const self = @as(*OpenGLSurface, @ptrCast(@alignCast(ptr)));

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
