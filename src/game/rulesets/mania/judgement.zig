const Replay = @import("../../formats/Replay.zig");
const Replayer = @import("./Replayer.zig");

// Judge a Mania replay.
pub fn judge(columns: u8, objects: []Replayer.Object, replay: *Replay) !void {
    var timestamp = @as(i64, 0);
    var start = @as(u64, 0);

    var previous_columns_bitmap = @as(?u16, null);

    for (replay.frames) |frame| {
        const column_bitmap = @as(u16, @intFromFloat(@trunc(frame.x)));

        for (0..columns) |column| {
            for (objects[start..]) |*object| {
                if (object.column == column) {
                    if (object.end == null) {
                        // The object is a "note". 

                        if (object.press == null) {
                            if (column_bitmap & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and @abs(timestamp - object.start) <= Timing.meh) {
                                object.press = timestamp;

                                start += 1;

                                break;
                            }
                        } 

                        if (timestamp > object.start + Timing.meh) {
                            start += 1;

                            break;
                        }
                    } else {
                        // The object is a "hold".

                        if (object.press == null) {
                            if (column_bitmap & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and @abs(timestamp - object.start) <= Timing.meh) {
                                object.press = timestamp;
                            }
                        } else if (object.release == null) {
                            if (previous_columns_bitmap.? & (@as(u32, 1) << @as(u5, @intCast(column))) != 0 and column_bitmap & (@as(u32, 1) << @as(u5, @intCast(column))) == 0) {
                                if (@abs(timestamp - object.end.?) < Timing.meh) {
                                    object.release = timestamp;

                                    start += 1;

                                    break;
                                }
                            }
                        }

                        if (timestamp > object.end.? + Timing.meh) {
                            start += 1;

                            break;
                        }
                    }
                } 
            }
        }

        timestamp += frame.w;
        previous_columns_bitmap = column_bitmap;
    }
}

// The timing.
pub const Timing = .{
    .perfect = 16,
    .great = 64,
    .good = 97,
    .ok = 127,
    .meh = 151,
    .miss = 188
};
