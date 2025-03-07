const std = @import("std");

const Surface = @import("../graphic/Surface.zig");
const Texture = @import("../graphic/Texture.zig");
const Color = @import("../graphic/Color.zig");

const Playfield = @This();

surface: *Surface,
scale: f32,

width: u16,
height: u16,
x: u16,
y: u16,


// Initialize a playfield.
pub fn init(surface: *Surface, width: u16, height: u16) Playfield {
    const scale = @min(
        @as(f32, @floatFromInt(surface.width)) / @as(f32, @floatFromInt(width)),
        @as(f32, @floatFromInt(surface.height)) / @as(f32, @floatFromInt(height)) 
    );

    const playfield_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * scale));
    const playfield_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(height)) * scale));

    return Playfield{
        .surface = surface, 
        .scale = scale,

        .x = @divFloor(surface.width, 2) - @divFloor(playfield_width, 2),
        .y = @divFloor(surface.height, 2) - @divFloor(playfield_height, 2),
        .width = width,
        .height = height,
    };
}

// Clear the playfield.
pub fn clear(self: *Playfield) !void {
    try self.surface.clear();
}

// Fill the playfield.
pub fn fill(self: *Playfield, color: Color) !void {
    try self.surface.fill(color);
}

// Draw a rectangle.
pub fn drawRectangle(self: *Playfield, color: Color, x: i17, y: i17, width: u16, height: u16, origin: ?Alignment, anchor: ?Alignment) !void {
    var position = self.calculatePosition(x, y, width, height, origin orelse Alignment.TopLeft, anchor orelse Alignment.TopLeft);

    position[0] = @as(i17, @intFromFloat(@as(f32, @floatFromInt(position[0])) * self.scale));
    position[1] = @as(i17, @intFromFloat(@as(f32, @floatFromInt(position[1])) * self.scale));

    try self.surface.drawRectangle(
        color,
        self.x + position[0],
        self.y + position[1],
        @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * self.scale)),
        @as(u16, @intFromFloat(@as(f32, @floatFromInt(height)) * self.scale))
    );
}

// Draw a texture.
pub fn drawTexture(self: *Playfield, texture: Texture, x: i17, y: i17, width: ?u16, height: ?u16, origin: ?Alignment, anchor: ?Alignment) !void {
    if (width == null and height == null) {
        return error.NoSizeProvided;
    }

    var scaled_width = @as(u16, undefined);
    var scaled_height = @as(u16, undefined);

    if (width == null) {
        const scale = @as(f32, @floatFromInt(texture.width)) / @as(f32, @floatFromInt(texture.height));

        scaled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(height.?)) * scale));
        scaled_height = height.?;
    } else if (height == null) {
        const scale = @as(f32, @floatFromInt(texture.height)) / @as(f32, @floatFromInt(texture.width));

        scaled_width = width.?;
        scaled_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width.?)) * scale));
    }

    var position = self.calculatePosition(x, y, scaled_width, scaled_height, origin orelse Alignment.TopLeft, anchor orelse Alignment.TopLeft);

    position[0] = @as(i17, @intFromFloat(@as(f32, @floatFromInt(position[0])) * self.scale));
    position[1] = @as(i17, @intFromFloat(@as(f32, @floatFromInt(position[1])) * self.scale));

    try self.surface.drawTexture(
        texture,
        self.x + position[0],
        self.y + position[1],
        @as(u16, @intFromFloat(@as(f32, @floatFromInt(scaled_width)) * self.scale)),
        @as(u16, @intFromFloat(@as(f32, @floatFromInt(scaled_height)) * self.scale))
    );
}

// Calculate the position.
fn calculatePosition (self: *Playfield, x: i17, y: i17, width: u16, height: u16, origin: Alignment, anchor: Alignment) [2]i17 {
    var calculated_x = @as(i17, undefined);
    var calculated_y = @as(i17, undefined);

    const playfield_width = @as(i17, @intCast(self.width));
    const playfield_height = @as(i17, @intCast(self.height));
    const local_width = @as(i17, @intCast(width));
    const local_height = @as(i17, @intCast(height));

    switch (anchor) {
        .TopLeft => {
            calculated_x = 0;
            calculated_y = 0;
        },
        .TopCenter => {
            calculated_x = @divFloor(playfield_width, 2);
            calculated_y = 0;
        },
        .TopRight => {
            calculated_x = playfield_width;
            calculated_y = 0;
        },

        .CenterLeft => {
            calculated_x = 0;
            calculated_y = @divFloor(playfield_height, 2);
        },
        .Center => {
            calculated_x = @divFloor(playfield_width, 2);
            calculated_y = @divFloor(playfield_height, 2);
        },
        .CenterRight => {
            calculated_x = playfield_width;
            calculated_y = @divFloor(playfield_height, 2);
        },
        
        .BottomLeft => {
            calculated_x = 0;
            calculated_y = playfield_height;
        },
        .BottomCenter => {
            calculated_x = @divFloor(playfield_height, 2);
            calculated_y = playfield_height;
        },
        .BottomRight => {
            calculated_x = playfield_width;
            calculated_y = playfield_height;
        }
    }

    calculated_x +|= x;
    calculated_y +|= y;

    switch (origin) {
        .TopLeft => {
            calculated_x = calculated_x;
            calculated_y = calculated_y;
        },
        .TopCenter => {
            calculated_x = calculated_x - @divFloor(local_width, 2);
            calculated_y = calculated_y;
        },
        .TopRight => {
            calculated_x = calculated_x - local_width;
            calculated_y = calculated_y;
        },

        .CenterLeft => {
            calculated_x = calculated_x;
            calculated_y = calculated_y - @divFloor(local_height, 2);
        },
        .Center => {
            calculated_x = calculated_x - @divFloor(local_width, 2);
            calculated_y = calculated_y - @divFloor(local_height, 2);
        },
        .CenterRight => {
            calculated_x = calculated_x - local_width;
            calculated_y = calculated_y - @divFloor(local_height, 2);
        },

        .BottomLeft => {
            calculated_x = calculated_x;
            calculated_y = calculated_y - local_height;
        },
        .BottomCenter => {
            calculated_x = calculated_x - @divFloor(local_width, 2);
            calculated_y = calculated_y - local_height;
        },
        .BottomRight => {
            calculated_x = calculated_x - local_width;
            calculated_y = calculated_y - local_height;
        }
    }

    return .{calculated_x, calculated_y};
}

// The alignment.
pub const Alignment = enum(u4) {
    TopLeft,
    TopCenter,
    TopRight,
    CenterLeft,
    Center,
    CenterRight,
    BottomLeft,
    BottomCenter,
    BottomRight
};
