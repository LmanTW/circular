const builtin = @import("builtin");
const std = @import("std");

const Storage = @This();

allocator: std.mem.Allocator,

home_path: []const u8,
circular_path: []const u8,
beatmaps_path: []const u8,

// Initialize a storage.
pub fn init(allocator: std.mem.Allocator) !Storage {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const home_path = switch (builtin.target.os.tag) {
        .linux, .macos => env.get("HOME"),
        .windows => env.get("%HOMEPATH%"),

        else => @compileError("Unsupported platform")
    } orelse {
        return error.HomeDirectionNotFound;
    };

    const circular_path = try std.fs.path.join(allocator, &.{home_path, ".circular"});
    const beatmaps_path = try std.fs.path.join(allocator, &.{circular_path, "beatmaps"});
    
    std.fs.makeDirAbsolute(circular_path) catch {};
    std.fs.makeDirAbsolute(beatmaps_path) catch {};

    return Storage{
        .allocator = allocator,

        .home_path = home_path,
        .circular_path = circular_path,
        .beatmaps_path = beatmaps_path
    };
}

// Deinitialize the storage.
pub fn deinit(self: *Storage) void {
    self.allocator.free(self.circular_path);
    self.allocator.free(self.beatmaps_path);
}

// Clean the storage.
pub fn clean(self: *Storage) !void {
    var directory = try std.fs.openDirAbsolute(self.beatmaps_path, .{});
    defer directory.close();

    var iterator = directory.iterate();
    var files = @as(usize, 0);

    var oldest_filename = @as(?[]const u8, null);
    var oldest_date = @as(?i128, null);

    while (true) {
        while (try iterator.next()) |entry| {
            const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, entry.name});
            defer self.allocator.free(beatmap_path);

            const file = try std.fs.openFileAbsolute(beatmap_path, .{});
            defer file.close();

            const stat = try file.stat();

            if (oldest_date == null or oldest_date.? < stat.atime) {
                oldest_filename = entry.name;
                oldest_date = stat.atime;
            }

            files += 1;
        }

        if (files > 99 and oldest_filename != null) {
            const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, oldest_filename.?});
            defer self.allocator.free(beatmap_path);

            try std.fs.deleteFileAbsolute(beatmap_path);

            files -= 1;

            if (files <= 99) {
                oldest_filename = null;
                oldest_date = null;

                continue;
            }
        }

        break;
    } 
}

// Check a beatmap.
pub fn checkBeatmap(self: *Storage, hash: []const u8) !bool {
    const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, hash});
    defer self.allocator.free(beatmap_path);

    std.fs.accessAbsolute(beatmap_path, .{}) catch {
        return false;
    };

    return true;
}

// Get a beatmap.
pub fn getBeatmap(self: *Storage, hash: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (!try self.checkBeatmap(hash)) {
        return error.BeatmapNotFound;
    }

    const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, hash});
    defer self.allocator.free(beatmap_path);

    const file = try std.fs.openFileAbsolute(beatmap_path, .{});
    defer file.close();

    const buffer = try allocator.alloc(u8, try file.getEndPos());
    _ = try file.readAll(buffer);

    return buffer;
}

// Download a beatmap.
pub fn downloadBeatmap(self: *Storage, hash: []const u8) !void {
    if (try self.checkBeatmap(hash)) {
        return error.BeatmapExists;
    }

    var info_response = try fetch("https://catboy.best/api/v2/md5/{s}", .{hash}, self.allocator);
    defer info_response.deinit();

    const beatmap_info = try std.json.parseFromSlice(struct { beatmapset_id: u32, id: u32 }, self.allocator, info_response.items, .{
        .ignore_unknown_fields = true
    });
    defer beatmap_info.deinit();

    var data_response = try fetch("https://catboy.best/d/{}", .{beatmap_info.value.beatmapset_id}, self.allocator);
    defer data_response.deinit();

    const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, hash});
    defer self.allocator.free(beatmap_path);

    const file = try std.fs.createFileAbsolute(beatmap_path, .{});
    defer file.close();

    try file.writeAll(data_response.items);
}

// Perform a one-shot HTTP request.
fn fetch(comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(url);

    var response_storage = std.ArrayList(u8).init(allocator);

    const response = try client.fetch(.{
        .location = .{
            .url = url,
        },

        .response_storage = .{ .dynamic = &response_storage },
        .max_append_size = std.math.maxInt(u32)
    });

    if (response.status != .ok) {
        return error.RequestFailed;
    }

    return response_storage;
}
