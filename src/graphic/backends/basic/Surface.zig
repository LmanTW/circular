const std = @import("std");

const BasicTexture = @import("./Texture.zig");
const Surface = @import("../../Surface.zig");
const Texture = @import("../../Texture.zig");
const Color = @import("../../Color.zig");
const Worker = @import("./Worker.zig");

const BasicSurface = @This();

allocator: std.mem.Allocator,
pixels: []u8,

width: u16,
height: u16,

workers: Worker.Group,

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
pub fn init(width: u16, height: u16, threads: u8, allocator: std.mem.Allocator) !BasicSurface {
    const pixels = try allocator.alloc(u8, (@as(u64, @intCast(width)) * height) * 4);
    errdefer allocator.free(pixels);

    @memset(pixels, 0);

    return BasicSurface{
        .allocator = allocator,
        .pixels = pixels,

        .width = width,
        .height = height,
        
        .workers = try Worker.Group.init(threads, allocator)
    };
}

// Deinitialize the surface.
pub fn deinit(ptr: *anyopaque) void {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    self.allocator.free(self.pixels);
    self.workers.deinit();
}

// Get a pixel on the surface.
pub fn get(self: *BasicSurface, x: i17, y: i17) ?Color {
    if ((x >= 0 and x < self.width) and (y >= 0 and y < self.height)) {
        const offset = ((@as(u64, @intCast(y)) * self.width) + @as(u64, @intCast(x))) * 4;

        return self.getByOffset(offset);
    }

    return null;
}

// Get a pixel by the offset.
pub fn getByOffset(self: *BasicSurface, offset: u64) Color {
    return Color.init(
        self.pixels[offset],
        self.pixels[offset + 1],
        self.pixels[offset + 2],
        @as(f32, @floatFromInt(self.pixels[offset + 3])) / 255
    );
}

// Set a pixel on surface.
pub fn set(self: *BasicSurface, color: Color, x: i17, y: i17) void {
    if ((x >= 0 and x < self.width) and (y >= 0 and y < self.height)) {
        const offset = ((@as(u64, @intCast(y)) * self.width) + @as(u64, @intCast(x))) * 4;

        self.setByOffset(color, offset);
    }
}

// Set a pixel by the offset.
pub fn setByOffset(self: *BasicSurface, color: Color, offset: u64) void {
    if (color.a >= 1) {
        self.pixels[offset] = color.r;
        self.pixels[offset + 1] = color.g;
        self.pixels[offset + 2] = color.b;
        self.pixels[offset + 3] = 255;
    } else if (color.a > 0) {
        const new_color = Color.init(
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
            @as(f16, @floatFromInt(self.pixels[offset + 3])) / 255
        ).mix(color);

        self.pixels[offset] = new_color.r;
        self.pixels[offset + 1] = new_color.g;
        self.pixels[offset + 2] = new_color.b;
        self.pixels[offset + 3] = @as(u8, @intFromFloat(new_color.a * 255));
    }
}

// Clear the surface.
pub fn clear(ptr: *anyopaque) !void {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    @memset(self.pixels, 0);
}

// Fill the surface.
pub fn fill(ptr: *anyopaque, color: Color) !void {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    var ctx = FillContext{
        .surface = self,
        .color = color
    };

    try self.workers.assign(@as(*anyopaque, @ptrCast(&ctx)), fillTask, .{0, self.pixels.len / 4});
    try self.workers.wait();
}

// The task to fill the surface.
fn fillTask(ptr: *anyopaque, range: [2]u64) void {
    const ctx = @as(*FillContext, @ptrCast(@alignCast(ptr)));

    var offset = range[0] * 4;

    while (offset < range[1] * 4) {
        ctx.surface.setByOffset(ctx.color, offset);

        offset += 4;
    }
}

// The context of the task to fill the surface.
const FillContext = struct {
    surface: *BasicSurface,
    color: Color
};

// Draw a rectangle.
pub fn drawRectangle(ptr: *anyopaque, color: Color, x: i17, y: i17, width: u16, height: u16) !void {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    var ctx = DrawRectangleContext{
        .surface = self,
        .color = color,
            
        .x = x,
        .y = y,
        .width = width,
        .height = height
    };

    try self.workers.assign(@as(*anyopaque, @ptrCast(&ctx)), drawRectangleTask, .{0, if (width > height) width else height});
    try self.workers.wait();
}

// The task to draw a rectangle.
fn drawRectangleTask(ptr: *anyopaque, range: [2]u64) void {
    const ctx = @as(*DrawRectangleContext, @ptrCast(@alignCast(ptr)));

    const end_x = ctx.x +| @as(i17, @intCast(ctx.width));
    const end_y = ctx.y +| @as(i17, @intCast(ctx.height));

    if (ctx.width > ctx.height) {
        var x = ctx.x + @as(i17, @intCast(range[0]));
        var y = ctx.y;

        while (x < ctx.x +| end_x) {
            while (y < ctx.y +| end_y) {
                ctx.surface.set(ctx.color, x, y);

                y += 1;
            }

            x += 1;
            y = ctx.y;
        }
    } else {
        var x = ctx.x;
        var y = ctx.y + @as(i16, @intCast(range[0]));

        while (y < ctx.y +| end_y) {
            while (x < ctx.x +| end_x) {
                ctx.surface.set(ctx.color, x, y);

                x += 1;
            }

            x = ctx.x;
            y += 1;
        }
    }
}

// The context of the task to draw a rectangle.
const DrawRectangleContext = struct {
    surface: *BasicSurface,
    color: Color,

    x: i17,
    y: i17,
    width: u16,
    height: u16
};

// Draw a texture.
pub fn drawTexture(ptr: *anyopaque, texture: Texture, x: i17, y: i17, width: u16, height: u16) !void {
    if (texture.backend != .Basic) {
        return error.BackendMismatch;
    }

    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    var ctx = DrawTextureContext{
        .surface = self,
        .texture = @as(*BasicTexture, @ptrCast(@alignCast(texture.unmanaged))),
            
        .x = x,
        .y = y,
        .width = width,
        .height = height
    };

    try self.workers.assign(@as(*anyopaque, @ptrCast(&ctx)), drawTextureTask, .{0, if (width > height) width else height});
    try self.workers.wait();
}

// The task to draw a texture.
pub fn drawTextureTask(ptr: *anyopaque, range: [2]u64) void {
    const ctx = @as(*DrawTextureContext, @ptrCast(@alignCast(ptr)));

    const end_x = ctx.x +| @as(i17, @intCast(ctx.width));
    const end_y = ctx.y +| @as(i17, @intCast(ctx.height));
    const x_scale = @as(f32, @floatFromInt(ctx.texture.width)) / @as(f32, @floatFromInt(ctx.width));
    const y_scale = @as(f32, @floatFromInt(ctx.texture.height)) / @as(f32, @floatFromInt(ctx.height));

    if (ctx.width > ctx.height) {
        var surface_x = ctx.x + @as(i17, @intCast(range[0]));
        var surface_y = ctx.y;

        while (surface_x < end_x) {
            while (surface_y < end_y) {
                const texture_x = @as(u16, @intFromFloat(@ceil(@as(f32, @floatFromInt(surface_x - ctx.x)) * x_scale)));
                const texture_y = @as(u16, @intFromFloat(@ceil(@as(f32, @floatFromInt(surface_y - ctx.y)) * y_scale)));
                const texture_offset = (@as(u64, @intCast(texture_y)) * 4) + texture_x;

                ctx.surface.set(Color.init(
                    ctx.texture.pixels[texture_offset],
                    ctx.texture.pixels[texture_offset + 1],
                    ctx.texture.pixels[texture_offset + 2],
                    @as(f32, @floatFromInt(ctx.texture.pixels[texture_offset + 3])) / 255
                ), surface_x, surface_y);

                surface_y += 1;
            }

            surface_x += 1;
            surface_y = ctx.y;
        }
    } else {
        var surface_x = ctx.x;
        var surface_y = ctx.y + @as(i17, @intCast(range[0]));

        while (surface_y < end_y) {
            while (surface_x < end_x) {
                const texture_x = @as(u16, @intFromFloat(@ceil(@as(f32, @floatFromInt(surface_x - ctx.x)) * x_scale)));
                const texture_y = @as(u16, @intFromFloat(@ceil(@as(f32, @floatFromInt(surface_y - ctx.y)) * y_scale)));
                const texture_offset = ((@as(u64, @intCast(texture_y)) * ctx.texture.width) + texture_x) * 4;

                ctx.surface.set(Color.init(
                    ctx.texture.pixels[texture_offset],
                    ctx.texture.pixels[texture_offset + 1],
                    ctx.texture.pixels[texture_offset + 2],
                    @as(f32, @floatFromInt(ctx.texture.pixels[texture_offset + 3])) / 255
                ), surface_x, surface_y);

                surface_x += 1;
            }

            surface_x = ctx.x;
            surface_y += 1;
        }
    }
}

// The context of the task to draw a texture.
const DrawTextureContext = struct {
    surface: *BasicSurface,
    texture: *BasicTexture,

    x: i17,
    y: i17,
    width: u16,
    height: u16
};

// Read the surface.
pub fn read(ptr: *anyopaque, format: Surface.Format, buffer: []u8) !void {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    const length = switch (format) {
        .RGB => (@as(u64, @intCast(self.width)) * self.height) * 3,
        .RGBA => (@as(u64, @intCast(self.width)) * self.height) * 4
    };

    if (buffer.len != length) {
        return error.InvalidBufferLength;
    }

    switch (format) {
        .RGB => {
            var pixel_offset = @as(u64, 0);
            var buffer_offset = @as(u64, 0);

            while (pixel_offset < self.pixels.len) {
                buffer[buffer_offset] = self.pixels[pixel_offset];
                buffer[buffer_offset + 1] = self.pixels[pixel_offset + 1];
                buffer[buffer_offset + 2] = self.pixels[pixel_offset + 2];

                pixel_offset += 4;
                buffer_offset += 3;
            }
        },

        .RGBA => {
            @memcpy(buffer, self.pixels);
        }
    }
}
