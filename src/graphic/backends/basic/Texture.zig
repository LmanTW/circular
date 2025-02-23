const stbi = @import("stbi");
const std = @import("std");

const Texture = @import("../../Texture.zig");

const BasicTexture = @This();

allocator: std.mem.Allocator,
pixels: []u8,

// The vtable.
pub const VTable = Texture.VTable{
    .deinit = deinit
};

// Initialize a texture.
pub fn init(buffer: []u8, allocator: std.mem.Allocator) !Texture {
    stbi.init(allocator);
    defer stbi.deinit();

    var image = try stbi.Image.loadFromMemory(buffer, 4);
    defer image.deinit();

    const pixels = try allocator.alloc(u8, image.data.len);
    @memcpy(pixels, image.data);

    const unmanaged = try allocator.create(BasicTexture);
    unmanaged.* = .{ .allocator = allocator, .pixels = pixels };

    return Texture{
        .allocator = allocator,
        .unmanaged = unmanaged,
            
        .width = @as(u16, @intCast(image.width)),
        .height = @as(u16, @intCast(image.height)),

        .backend = .Basic,
        .vtable = &VTable
    };
}

// Deinitialize the texture.
pub fn deinit(ptr: *anyopaque) void {
    const self = @as(*BasicTexture, @ptrCast(@alignCast(ptr)));

    self.allocator.free(self.pixels);
}
