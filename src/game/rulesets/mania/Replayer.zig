const std = @import("std");

const Surface = @import("../../../graphic/Surface.zig");
const Beatmap = @import("../../formats/Beatmap.zig");
const video = @import("../../../graphic/video.zig");
const Replay = @import("../../formats/Replay.zig");
const Replayer = @import("../../Replayer.zig");
const judgement = @import("./judgement.zig");

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
pub fn loadDifficulty(ptr: *anyopaque, difficulty: *Beatmap.Difficulty) !void {
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
    const self = @as(*ManiaReplayer, @ptrCast(@alignCast(ptr)));

    if (self.objects == null) {
        return error.BeatmapNotLoaded;
    }

    try judgement.judge(self, replay);
}

// Render a frame.
pub fn render(_: *anyopaque, _: *Surface, _: *video.Encoder, _: u64) !void {
}
