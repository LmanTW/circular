const std = @import("std");

const Texture = @import("../../../graphic/Texture.zig");
const Skin = @import("../../formats/Skin.zig");
const Textures = @import("../../Textures.zig");

const Appearance = @This();

columns_x: [18]u16,
columns_width: [18]u16,

// Initialize an appearance.
pub fn init(skin: *Skin, columns: u8) !Appearance {
    var name_buffer = @as([64]u8, undefined);

    const column_start = skin.parseField(u16, try std.fmt.bufPrint(&name_buffer, "Mania{}K.ColumnStart", .{columns}), 136);
    const column_width = skin.parseListField(u16, 18, try std.fmt.bufPrint(&name_buffer, "Mania{}K.ColumnWidth", .{columns}), 30);
    const column_spacing = skin.parseField(u16, try std.fmt.bufPrint(&name_buffer, "Mania{}K.ColumnSpacing", .{columns}), 0);

    var columns_x = @as([18]u16, undefined);
    var current_x = @as(u16, column_start);

    for (0..18) |index| {
        columns_x[index] = current_x;
        current_x +|= column_width[index] + column_spacing;
    }

    return Appearance{
        .columns_x = columns_x,
        .columns_width = column_width
    };
}
