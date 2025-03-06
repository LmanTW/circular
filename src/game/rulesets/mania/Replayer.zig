const std = @import("std");

const Surface = @import("../../../graphic/Surface.zig");
const Beatmap = @import("../../formats/Beatmap.zig");
const video = @import("../../../graphic/video.zig");
const Color = @import("../../../graphic/Color.zig");
const Replay = @import("../../formats/Replay.zig");
const Playfield = @import("../../Playfield.zig");
const Replayer = @import("../../Replayer.zig");

const ManiaReplayer = @This();

allocator: std.mem.Allocator,
objects: ?[]Object,

columns: u8,

// The vtable.
pub const VTable = Replayer.VTable{
    .deinit = deinit,

    .loadDifficulty = loadDifficulty,
    .loadReplay = loadReplay,

    .render = render
};

// The object.
// > If [end] is not <null>, it means the object is a "hold".
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
        .objects = null,

        .columns = 0
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

        const column = std.math.clamp(@as(u4, @intFromFloat(@floor(try std.fmt.parseFloat(f32, x.?) * (@as(f32, @floatFromInt(self.columns)) / 512)))) , 0, self.columns - 1);

        switch (try std.fmt.parseInt(u8, kind.?, 10)) {
            1 => {
                try objects.append(.{
                    .column = column,

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
                    .column = column,

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
pub fn loadReplay(ptr: *anyopaque, replay: *Replay) !void {
    if (replay.ruleset != .Mania) {
        return error.RulesetMismatch;
    }

    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.objects == null) {
        return error.BeatmapNotLoaded;
    }

    var timestamp = @as(i64, 0);
    var start = @as(u64, 0);

    var previous_columns = @as(?u16, null);

    for (replay.frames) |frame| {
        const columns = @as(u16, @intFromFloat(@trunc(frame.x)));

        for (0..self.columns) |column| {
            for (self.objects.?[start..]) |*object| {
                if (object.column == column) {
                    if (object.end == null) {
                        // The object is a "note". 

                        if (object.press == null) {
                            if (columns & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and @abs(timestamp - object.start) < 151) {
                                object.press = timestamp;

                                start += 1;

                                break;
                            }
                        } 

                        if (timestamp > object.start + 151) {
                            start += 1;

                            break;
                        }
                    } else {
                        // The object is a "hold".

                        if (object.press == null) {
                            if (columns & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and @abs(timestamp - object.start) < 151) {
                                object.press = timestamp;
                            }
                        } else if (object.release == null) {
                            if (previous_columns.? & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and columns & (@as(u32, 1) << @as(u5, @intCast(column))) == 0) {
                                if (@abs(timestamp - object.end.?) < 151) {
                                    object.release = timestamp;

                                    start += 1;

                                    break;
                                }
                            }
                        }

                        if (timestamp > object.end.? + 151) {
                            start += 1;

                            break;
                        }
                    }
                } 
            }
        }

        timestamp += frame.w;
        previous_columns = columns;
    }
}

// Render a frame.
pub fn render(ptr: *anyopaque, surface: *Surface, timestamp: u64) !void {
    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.objects == null) {
        return error.BeatmapNotLoaded;
    }

    var playfield = try Playfield.init(surface, @as(u16, @intCast(self.columns)) * 32, 256);
    try playfield.fill(Color.init(0, 0, 0, 1));

    for (self.objects.?) |object| {
        const abs = @abs(object.start - @as(i64, @intCast(timestamp))); 

        if (timestamp > object.start and abs < 256) {
            try playfield.drawRectangle(Color.init(255, 255, 255, 1), object.column * 32, @as(i17, @intCast(@divFloor(abs, 2))), 32, 16, null, null);
        }
    }
}
