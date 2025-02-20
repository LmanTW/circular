const std = @import("std");

const ManiaReplayer = @import("./rulesets/mania/Replayer.zig");
const Surface = @import("../graphic/Surface.zig");
const Beatmap = @import("./formats/Beatmap.zig");
const Replay = @import("./formats/Replay.zig");
const video = @import("../graphic/video.zig");

const Replayer = @This();

allocator: std.mem.Allocator,
unmanaged: *anyopaque,

ruleset: Ruleset,
vtable: *const VTable,

// The vtable.
pub const VTable = struct {
    deinit: *const fn(ptr: *anyopaque) void,

    loadDifficulty: *const fn(ptr: *anyopaque, difficulty: *Beatmap.Difficulty) anyerror!void,
    loadReplay: *const fn(ptr: *anyopaque, replay: *Replay) anyerror!void,

    render: *const fn(ptr: *anyopaque, surface: *Surface, encoder: *video.Encoder, timestamp: u64) anyerror!void
};

// Initialize a replayer.
pub fn init(ruleset: Ruleset, allocator: std.mem.Allocator) !Replayer {
    switch (ruleset) {
        .Mania => {
            const unmanaged = try allocator.create(ManiaReplayer);
            errdefer allocator.destroy(unmanaged);

            unmanaged.* = try ManiaReplayer.init(allocator);

            return Replayer{
                .allocator = allocator,
                .unmanaged = unmanaged,

                .ruleset = ruleset,
                .vtable = &ManiaReplayer.VTable
            };
        }
    }
}

// Deinitialize the replayer.
pub fn deinit(self: *Replayer) void {
    self.vtable.deinit(self.unmanaged);

    switch (self.ruleset) {
        .Mania => self.allocator.destroy(@as(*ManiaReplayer, @ptrCast(@alignCast(self.unmanaged)))),
    }
}

// Load a difficulty.
pub fn loadDifficulty(self: *Replayer, difficulty: *Beatmap.Difficulty) !void {
    try self.vtable.loadDifficulty(self.unmanaged, difficulty);
}

// Load a replay.
pub fn loadReplay(self: *Replayer, replay: *Replay) !void {
    try self.vtable.loadReplay(self.unmanaged, replay);
}

// Render a frame.
pub fn render(self: *Replayer, surface: *Surface, encoder: *video.Encoder, timestamp: u64) !void {
    try self.vtable.render(self.unmanaged, surface, encoder, timestamp);
}

// The ruleset.
pub const Ruleset = enum(u4) {
    Mania
};
