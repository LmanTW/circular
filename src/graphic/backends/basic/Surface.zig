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

    .loadTexture = loadTexture,
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
pub fn set(self: *BasicSurface, x: i17, y: i17, color: Color) void {
    if ((x >= 0 and x < self.width) and (y >= 0 and y < self.height)) {
        const offset = ((@as(u64, @intCast(y)) * self.width) + @as(u64, @intCast(x))) * 4;

        self.setByOffset(offset, color);
    }
}

// Set a pixel by the offset.
pub fn setByOffset(self: *BasicSurface, offset: u64, color: Color) void {
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

    var ctx = FillTaskContext{
        .surface = self,
        .color = color
    };

    try self.workers.assign(@as(*anyopaque, @ptrCast(&ctx)), fillTask, .{0, self.pixels.len / 4});
    try self.workers.wait();
}

// The task to fill the surface.
fn fillTask(ptr: *anyopaque, range: [2]u64) void {
    const ctx = @as(*FillTaskContext, @ptrCast(@alignCast(ptr)));

    var offset = range[0] * 4;

    while (offset < range[1] * 4) {
        ctx.surface.setByOffset(offset, ctx.color);

        offset += 4;
    }
}

// The context of the task to fill the surface.
const FillTaskContext = struct {
    surface: *BasicSurface,
    color: Color
};

// Load a texture.
pub fn loadTexture(ptr: *anyopaque, buffer: []u8) !Texture {
    const self = @as(*BasicSurface, @ptrCast(@alignCast(ptr)));

    return BasicTexture.init(buffer, self.allocator);
}

// Draw a texture.
pub fn drawTexture(_: *anyopaque, texture: Texture, _: i17, _: i17, _: u16, _: u16) !void {
    if (texture.backend != .Basic) {
        return error.BackendMismatch;
    }
}

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
