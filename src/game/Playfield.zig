const Surface = @import("../graphic/Surface.zig");

const Playfield = @This();

surface: *Surface,

width: u16,
height: u16,
x: u16,
y: u16,

// Initialize a playfield.
pub fn init(surface: *Surface) !Playfield {
    const scale = @min(
        @as(f32, @floatFromInt(surface.width)) / 512,
        @as(f32, @floatFromInt(surface.height)) / 384 
    );

    const width = @as(u16, @intFromFloat(512 * scale));
    const height = @as(u16, @intFromFloat(384 * scale));

    return Playfield{
        .surface = surface,

        .x = @divFloor(surface.width, 2) - @divFloor(width, 2),
        .y = @divFloor(surface.height, 2) - @divFloor(height, 2),
        .width = width,
        .height = height,
    };
}
