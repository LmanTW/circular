const std = @import("std");

const Surface = @import("../../../graphic/Surface.zig");
const Beatmap = @import("../../formats/Beatmap.zig");
const video = @import("../../../graphic/video.zig");
const Color = @import("../../../graphic/Color.zig");
const Replay = @import("../../formats/Replay.zig");
const Playfield = @import("../../Playfield.zig");
const Replayer = @import("../../Replayer.zig");
const Renderer = @import("../../Renderer.zig");
const Skin = @import("../../formats/Skin.zig");
const Appearance = @import("./Appearance.zig");
const judgement = @import("./judgement.zig");

const ManiaReplayer = @This();

allocator: std.mem.Allocator,
appearance: ?Appearance,

columns: ?u8,
objects: ?[]Object,

// The vtable.
pub const VTable = Replayer.VTable{
    .deinit = deinit,

    .loadDifficulty = loadDifficulty,
    .loadReplay = loadReplay,
    .loadSkin = loadSkin,

    .render = render
};

// The object.
// > If [end] is <null>, it means the object is a "note". Otherwise "hold".
pub const Object = struct {
    column: u8,

    start: i64,
    end: ?i64,

    press: ?i64,
    release: ?i64
};

// Initialize a replayer.
pub fn init(allocator: std.mem.Allocator) !ManiaReplayer {
    return ManiaReplayer{
        .allocator = allocator,
        .appearance = null, 

        .columns = null,
        .objects = null
    };
}

// Deinitialize the replayer.
pub fn deinit(ptr: *anyopaque) void {
    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.objects) |objects| {
        self.allocator.free(objects);
    }
}

// Load a difficulty.
// > [difficulty] is no longer required after loaded.
pub fn loadDifficulty(ptr: *anyopaque, difficulty: *Beatmap.Difficulty) !void {
    if (difficulty.parseField(u4, "General.Mode", 0) != 3) {
        return error.RulesetMismatch;
    }

    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.objects) |objects| {
        self.allocator.free(objects);
    }

    var objects = std.ArrayList(Object).init(self.allocator);
    errdefer objects.deinit();

    self.columns = difficulty.parseField(u4, "Difficulty.CircleSize", 1);

    for (difficulty.objects) |object| {
        var iterator = std.mem.tokenizeAny(u8, object, ",:");

        const x = iterator.next();
        const y = iterator.next();
        const time = iterator.next();
        const kind = iterator.next();
        const sound = iterator.next();

        if (x == null or y == null or time == null or kind == null or sound == null) {
            return error.IncompleteObject;
        } 

        switch (try std.fmt.parseInt(u8, kind.?, 10)) {
            1 => {
                try objects.append(.{
                    .column = std.math.clamp(@as(u4, @intFromFloat(@floor(try std.fmt.parseFloat(f32, x.?) * (@as(f32, @floatFromInt(self.columns.?)) / 512)))) , 0, self.columns.? - 1),

                    .start = try std.fmt.parseInt(i64, time.?, 10),
                    .end = null,

                    .press = null,
                    .release = null
                });
            },

            128 => {
                const end = iterator.next(); 

                if (end == null) {
                    return error.IncompleteHold;
                }

                try objects.append(.{
                    .column = std.math.clamp(@as(u4, @intFromFloat(@floor(try std.fmt.parseFloat(f32, x.?) * (@as(f32, @floatFromInt(self.columns.?)) / 512)))) , 0, self.columns.? - 1),

                    .start = try std.fmt.parseInt(i64, time.?, 10),
                    .end = try std.fmt.parseInt(i64, end.?, 10),

                    .press = null,
                    .release = null
                });
            },

            else => {}
        }
    }

    self.objects = try objects.toOwnedSlice();
}

// Load a replay.
// > [replay] is no longer required after loaded.
pub fn loadReplay(ptr: *anyopaque, replay: *Replay) !void {
    if (replay.ruleset != .Mania) {
        return error.RulesetMismatch;
    }

    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.columns == null or self.objects == null) {
        return error.BeatmapNotLoaded;
    }

    try judgement.judge(self.columns.?, self.objects.?, replay);
}

// Load a skin into the texture pool.
// > [skin] is no longer required after loaded.
pub fn loadSkin(ptr: *anyopaque, skin: *Skin, renderer: *Renderer) !void {
    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.columns == null or self.objects == null) {
        return error.BeatmapNotLoaded;
    }

    renderer.textures.clear();

    var field_name_buffer = @as([64]u8, undefined);
    var texture_name_buffer = @as([64]u8, undefined);

    for (0..17) |column| {
//        const flip_note_head = skin.parseField(u1, try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.NoteFlipWhenUpsideDown{}H", .{self.columns.?, column}), 1);
//        const flip_note_tail = skin.parseField(u1, try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.NoteFlipWhenUpsideDown{}T", .{self.columns.?, column}), 1);

        try renderer.textures.loadTexture(
            try std.fmt.bufPrint(&texture_name_buffer, "mania-note{}", .{column}),
            try skin.getImage(skin.getField(try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.NoteImage{}", .{self.columns.?, column}), if (column % 2 == 0) "mania-note1" else "mania-note2")),
            if (column % 2 == 0) @embedFile("../../assets/default/mania-note1@2x.png") else @embedFile("../../assets/default/mania-note2@2x.png"),
            .{}
        );
        try renderer.textures.loadTexture(
            try std.fmt.bufPrint(&texture_name_buffer, "mania-note-hold-head{}", .{column}),
            try skin.getImage(skin.getField(try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.NoteImage{}H", .{self.columns.?, column}), if (column % 2 == 0) "mania-note1" else "mania-note2")),
            if (column % 2 == 0) @embedFile("../../assets/default/mania-note1H@2x.png") else @embedFile("../../assets/default/mania-note2H@2x.png"),
            .{}
        );
        try renderer.textures.loadTexture(
            try std.fmt.bufPrint(&texture_name_buffer, "mania-note-hold-tail{}", .{column}),
            try skin.getImage(skin.getField(try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.NoteImage{}T", .{self.columns.?, column}), if (column % 2 == 0) "mania-note1" else "mania-note2")),
            if (column % 2 == 0) @embedFile("../../assets/default/mania-note1H@2x.png") else @embedFile("../../assets/default/mania-note2H@2x.png"),
            .{}
        );

        try renderer.textures.loadTexture(
            try std.fmt.bufPrint(&texture_name_buffer, "mania-key{}", .{column}),
            try skin.getImage(skin.getField(try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.KeyImage{}", .{self.columns.?, column}), if (column % 2 == 0) "mania-key1" else "mania-key2")),
            if (column % 2 == 0) @embedFile("../../assets/default/mania-key1@2x.png") else @embedFile("../../assets/default/mania-key2@2x.png"),
            .{}
        );
        try renderer.textures.loadTexture(
            try std.fmt.bufPrint(&texture_name_buffer, "mania-key{}-hold", .{column}),
            try skin.getImage(skin.getField(try std.fmt.bufPrint(&field_name_buffer, "Mania{}K.KeyImage{}D", .{self.columns.?, column}), if (column % 2 == 0) "mania-key1D" else "mania-key2D")),
            if (column % 2 == 0) @embedFile("../../assets/default/mania-key1D@2x.png") else @embedFile("../../assets/default/mania-key2@2x.png"),
            .{}
        );
    }

    self.appearance = try Appearance.init(skin, self.columns.?);
}

// Render a frame.
pub fn render(ptr: *anyopaque, renderer: *Renderer, timestamp: u64) !void {
    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.columns == null or self.objects == null)
        return error.BeatmapNotLoaded;
    if (self.appearance == null)
        return error.SkinNotLoaded;

    var playfield = Playfield.init(&renderer.surface, 640, 480);
    try playfield.clear();

    const appearance = self.appearance.?;

    var texture_name_buffer = @as([64]u8, undefined);

    for (self.objects.?) |object| {
        if (object.end == null) {
            // The object is a "note".

            if (timestamp < object.press orelse object.start) {
                const y = (@as(i64, @intCast(playfield.height)) - 32) - @divFloor(object.start - @as(i64, @intCast(timestamp)), 2);

                if (y > 0 and y < playfield.height) {
                    try playfield.drawTexture(
                        try renderer.textures.getTexture(try std.fmt.bufPrint(&texture_name_buffer, "mania-note{}", .{object.column})),
                        appearance.columns_x[object.column], @as(i17, @intCast(y)),
                        appearance.columns_width[object.column], null,
                        .BottomLeft, null
                    );
                }
            }
        } else {
            // The object is a "hold".

            const start_y = (@as(i64, @intCast(playfield.height)) - 32) - if (object.press != null and timestamp > object.press.?) 0 else @divFloor(object.start - @as(i64, @intCast(timestamp)), 2);
            const end_y = (@as(i64, @intCast(playfield.height)) - 32) - @divFloor(object.end.? - @as(i64, @intCast(timestamp)), 2);

            if (start_y > 0 and end_y < playfield.height and (start_y > end_y)) {
                // Draw the body of the "hold".

                try playfield.drawRectangle(
                    Color.init(255, 255, 255, 1),
                    appearance.columns_x[object.column], @as(i17, @intCast(start_y)),
                    appearance.columns_width[object.column], @as(u16, @intCast(start_y - end_y)),
                    .BottomLeft, null
                );
            }

            if (end_y > 0 and end_y < start_y) {
                //Draw the tail of the "hold".

                try playfield.drawTexture(
                    try renderer.textures.getTexture(try std.fmt.bufPrint(&texture_name_buffer, "mania-note-hold-tail{}", .{object.column})),
                    appearance.columns_x[object.column], @as(i17, @intCast(end_y)),
                    appearance.columns_width[object.column], null,
                    .BottomLeft, null
                );
            }

            if (start_y > 0 and end_y < playfield.height and (start_y > end_y)) {
                // Draw the head of the "hold".

                try playfield.drawTexture(
                    try renderer.textures.getTexture(try std.fmt.bufPrint(&texture_name_buffer, "mania-note-hold-head{}", .{object.column})),
                    appearance.columns_x[object.column], @as(i17, @intCast(start_y)),
                    appearance.columns_width[object.column], null,
                    .BottomLeft, null
                );
            }
        }
    }
}
