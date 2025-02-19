const builtin = @import("builtin");
const std = @import("std");

const Storage = @This();

allocator: std.mem.Allocator,
circular_path: []const u8,
beatmaps_path: []const u8,

// Initialize a storage.
pub fn init(allocator: std.mem.Allocator) !Storage {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const home_path = switch (builtin.target.os.tag) {
        .linux, .macos => env.get("HOME"),
        .windows => env.get("HOMEPATH"),

        else => @compileError("Unsupported platform")
    } orelse {
        return error.HomeDirectionNotFound;
    };

    const circular_path = try std.fs.path.join(allocator, &.{home_path, ".circular"});
    const beatmaps_path = try std.fs.path.join(allocator, &.{circular_path, "beatmaps"});

    std.fs.accessAbsolute(circular_path, .{}) catch {
        try std.fs.makeDirAbsolute(circular_path);
    };
    std.fs.accessAbsolute(beatmaps_path, .{}) catch {
        try std.fs.makeDirAbsolute(beatmaps_path);
    };

    return Storage{
        .allocator = allocator,
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

    while (true) {
        var directory_iterator = directory.iterate();

        var file_amount = @as(usize, 0);
        var oldest_filename = @as(?[]const u8, null);
        var oldest_date = @as(?i128, null);

        while (try directory_iterator.next()) |entry| {
            const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, entry.name});
            defer self.allocator.free(beatmap_path);

            const file = try std.fs.openFileAbsolute(beatmap_path, .{});
            defer file.close();

            const stat = try file.stat();

            if (oldest_date == null or oldest_date.? < stat.atime) {
                oldest_filename = entry.name;
                oldest_date = stat.atime;
            }

            file_amount += 1;
        }

        if (file_amount > 99 and oldest_filename != null) {
            const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, oldest_filename.?});
            defer self.allocator.free(beatmap_path);

            try std.fs.deleteFileAbsolute(beatmap_path);

            file_amount -= 1;

            if (file_amount < 100) {
                continue;
            }
        }

        break;
    }
}

// Check if a beatmap is downlaoded.
pub fn checkBeatmap(self: *Storage, hash: []const u8) !bool {
    const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, hash});
    defer self.allocator.free(beatmap_path);

    std.fs.accessAbsolute(beatmap_path, .{}) catch {
        return false;
    };

    return true;
}

// Read a beatmap.
pub fn readBeatmap(self: *Storage, hash: []const u8, allocator: std.mem.Allocator) ![]u8 {
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
pub fn downlaodBeatmap(self: *Storage, hash: []const u8) !void {
    const info_response = try fetch("https://catboy.best/api/v2/md5/{s}", .{hash}, self.allocator);
    defer self.allocator.free(info_response);

    const parsed_info = try std.json.parseFromSlice(struct { beatmapset_id: u32 }, self.allocator, info_response, .{
        .ignore_unknown_fields = true
    });
    defer parsed_info.deinit();

    const data_response = try fetch("https://catboy.best/d/{}", .{parsed_info.value.beatmapset_id}, self.allocator);
    defer self.allocator.free(data_response);

    const beatmap_path = try std.fs.path.join(self.allocator, &.{self.beatmaps_path, hash});
    defer self.allocator.free(beatmap_path);

    if (try self.checkBeatmap(hash)) {
        const file = try std.fs.openFileAbsolute(beatmap_path, .{});
        defer file.close();

        try file.writeAll(data_response);
    } else {
        const file = try std.fs.createFileAbsolute(beatmap_path, .{});
        defer file.close();

        try file.writeAll(data_response);
    }
}

// Perform a one-shot HTTP request.
fn fetch(comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(url);

    var response_storage = std.ArrayList(u8).init(allocator);
    errdefer response_storage.deinit();

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

    return try response_storage.toOwnedSlice();
}
