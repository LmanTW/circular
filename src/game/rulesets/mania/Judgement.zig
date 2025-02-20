const std = @import("std");

const Replay = @import("../../formats/Replay.zig");
const Replayer = @import("./Replayer.zig");

// Judge a replay.
pub fn judge(replayer: *Replayer, replay: *Replay) !void {
    if (replayer.objects == null) {
        return error.ObjectsNotLoaded;
    }

    var timestamp = @as(i64, 0);
    var index = @as(u64, 0);

    for (replay.frames) |frame| {
        const columns = @as(u16, @intFromFloat(@trunc(frame.x)));

        for (0..replayer.columns) |column| {
            if (columns & (@as(u32, 1) << @as(u5, @intCast(column))) != 0) {
                while (index < replayer.objects.?.len and timestamp > replayer.objects.?[index].start - 151) {
                    const object = &replayer.objects.?[index];

                    if (object.column == column and object.release == null and object.press == null) {
                        if (@abs(timestamp - object.start) < 151) {
                            object.press = timestamp;
                        }
                    }

                    if (timestamp > object.start + 151) {
                        break;
                    }

                    index += 1;
                }
            }
        }

        timestamp += frame.w;
    }
}
