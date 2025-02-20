const std = @import("std");

const Replay = @import("../../formats/Replay.zig");
const Replayer = @import("./Replayer.zig");

// Judge a replay.
pub fn judge(replayer: *Replayer, replay: *Replay) void {
    var timestamp = @as(i64, 0);

    for (replay.frames) |frame| {
        const columns = @as(u16, @intFromFloat(@trunc(frame.x)));

        for (0..replayer.columns) |index| {
            if (columns & (@as(u32, 1) << @as(u5, @intCast(index))) != 0) {
                for (replayer.objects.?) |*object| {
                    if (object.column == index and object.press == null) {
                        if (@abs(timestamp - object.start) < 151) {
                            object.press = timestamp;
                        }
                    }
                }

            }
        }

        timestamp += frame.w;
    }
}
