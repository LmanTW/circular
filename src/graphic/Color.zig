const std = @import("std");

const Color = @This();

r: u8,
g: u8,
b: u8,
a: f32,

// Initialize a color.
pub fn init(r: u8, g: u8, b: u8, a: f32) Color {
    return Color{
        .r = r,
        .g = g,
        .b = b,
        .a = a
    };
}

// Initialize a color from hex.
pub fn initFromHex(hex: []const u8, alpha: f32) !Color {
    const offset = @as(u4, if (hex[0] == '#') 1 else 0);

    if (hex.len - offset != 6) {
        return error.InvalidLength;
    }

    return Color{
        .r = try std.fmt.parseInt(u8, hex[offset..offset + 2], 16),
        .g = try std.fmt.parseInt(u8, hex[offset + 2..offset + 4], 16),
        .b = try std.fmt.parseInt(u8, hex[offset + 4..offset + 6], 16),
        .a = alpha
    };
}

// Mix the color with another color.
pub fn mix(self: *const Color, color: Color) Color {
    if (color.a < 0) return Color.init(0, 0, 0, 0);
    if (color.a > 1) return color;

    const normalized_alpha = std.math.clamp(color.a, 0, 1);

    const red_distance = @as(f16, @floatFromInt(@as(i9, @intCast(color.r)) - @as(i9, @intCast(self.r))));
    const green_distance = @as(f16, @floatFromInt(@as(i9, @intCast(color.g)) - @as(i9, @intCast(self.g))));
    const blue_distance = @as(f16, @floatFromInt(@as(i9, @intCast(color.b)) - @as(i9, @intCast(self.b))));

    const red = @as(f32, @floatFromInt(self.r)) + (red_distance * normalized_alpha);
    const green = @as(f32, @floatFromInt(self.g)) + (green_distance * normalized_alpha);
    const blue = @as(f32, @floatFromInt(self.b)) + (blue_distance * normalized_alpha);

    return Color.init(
        @as(u8, @intFromFloat(std.math.clamp(red, 0, 255))),
        @as(u8, @intFromFloat(std.math.clamp(green, 0, 255))),
        @as(u8, @intFromFloat(std.math.clamp(blue, 0, 255))),
        normalized_alpha
    );
}
