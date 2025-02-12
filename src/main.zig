const std = @import("std");
const gl = @import("gl");

pub const Beatmap = @import("./formats/Beatmap.zig");
pub const Replay = @import("./formats/Replay.zig");

const Interface = @import("./Interface.zig");
const Storage = @import("./Storage.zig");

const Surface = @import("./graphic/Surface.zig");
const Color = @import("./graphic/Color.zig");
const video = @import("./graphic/video.zig");

// The main function :3
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Yes sir, your allocator.
    const allocator = gpa.allocator();

    var interface = try Interface.init(allocator);
    defer interface.deinit();

    if (interface.countArguments() > 0) {
        const current_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        const absolute_path = try std.fs.path.resolve(allocator, &.{current_path, interface.getArgument(0)});
        defer allocator.free(current_path);
        defer allocator.free(absolute_path);

        try interface.blank();
        try interface.log(.Running, "Reading the file: \"{s}\"", .{absolute_path});

        var replay = try loadReplay(absolute_path, &interface, allocator);
        defer replay.deinit(); 

        try interface.log(.Complete, "Succesfully parsed the replay!", .{});
        try interface.log(.Running, "Loading the beatmap...", .{});

        var beatmap = try loadBeatmap(replay.beatmap_hash, &interface, allocator);
        defer beatmap.deinit();

        try interface.log(.Complete, "Succesfully laoded the beatmap!", .{});
        try interface.log(.Running, "Loading the difficulty...", .{});

        var difficulty = try loadDifficulty(&beatmap, replay.beatmap_hash, &interface, allocator);
        defer difficulty.deinit();

        try interface.log(.Complete, "Succesfully load the difficulty!", .{});
        try interface.log(.Running, "Initializing the renderer...", .{});

        var surface = initSurface(&interface, allocator) catch {
            try interface.log(.Error, "Failed to initialize the renderer.", .{});
            try interface.blank();

            std.process.exit(1);
        };
        defer surface.deinit();

        try interface.log(.Complete, "Succesfully initialized the renderer!", .{});

        var encoder = try video.Encoder.init(interface.getOption("output", "replay.mp4"), surface.width, surface.height, interface.getOption("ffmpeg", "ffmpeg"), allocator);
        defer encoder.deinit();

        surface.fill(Color.init(255, 0, 0, 1));

        const buffer = try allocator.alloc(u8, (@as(u64, @intCast(surface.width)) * surface.height) * 3);
        defer allocator.free(buffer);

        try surface.read(.RGB, buffer);
        try encoder.addFrame(buffer);

        try encoder.finalize();
    } else {
        _ = try interface.stdout.write(
            \\
            \\ Circular (v0.1)
            \\   - The lightweight osu! replay renderer.
            \\
            \\ Usage:
            \\   circular [...options] [*.osr]
            \\
            \\ Options:
            \\   log="verbose"       | The logging format. ("none", "verbose", "json")
            \\
            \\   fps=30              | The frame rate of the video.
            \\   width=1280          | The width of the video.
            \\   height=720          | The height of the video.
            \\
            \\   output="replay.mp4" | The filename of the output video.
            \\
            \\   backend="opengl"    | The rendering backend. ("basic", "opengl")
            \\   threads="auto"      | The amount CPU threads to use.
            \\
            \\   ffmpeg="ffmpeg"     | The command/path to ffmpeg.
            \\
            \\
        );
    }
}

// Load the replay.
pub fn loadReplay(absolute_path: []const u8, interface: *Interface, allocator: std.mem.Allocator) !Replay {
    const file = std.fs.openFileAbsolute(absolute_path, .{}) catch {
        try interface.log(.Error, "Failed to open the file.", .{});
        try interface.blank();

        std.process.exit(1);
    };
    defer file.close();

    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    try interface.log(.Complete, "Succesfully read the file!", .{});
    try interface.log(.Running, "Parsing the replay...", .{});

    const replay = Replay.initFromMemory(buffer, allocator) catch {
        try interface.log(.Error, "Failed to parse the replay.", .{});
        try interface.blank();

        std.process.exit(1);
    }; 

    return replay;
}

// Load the beatmap.
pub fn loadBeatmap(hash: []const u8, interface: *Interface, allocator: std.mem.Allocator) !Beatmap {
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    
    if (!try storage.checkBeatmap(hash)) {
        try interface.log(.Progress, "Downloading the beatmap...", .{});

        storage.downloadBeatmap(hash) catch {
            try interface.log(.Error, "Failed to download the beatmap.", .{});
            try interface.blank();

            std.process.exit(1);
        };

        try interface.log(.Progress, "Succesfully downloaded the beatmap!", .{});
    }

    try storage.clean();

    const buffer = try storage.getBeatmap(hash, allocator);
    defer allocator.free(buffer);

    const beatmap = Beatmap.initFromMemory(buffer, allocator) catch {
        try interface.log(.Error, "Failed to load the beatmap.", .{});
        try interface.blank();

        std.process.exit(1);
    };

    return beatmap;
}

// Load the difficulty.
pub fn loadDifficulty(beatmap: *Beatmap, hash: []const u8, interface: *Interface, allocator: std.mem.Allocator) !Beatmap.Difficulty {
    const difficulty = beatmap.findDifficulty(hash, allocator) catch {
        try interface.log(.Error, "Failed to load the difficulty.", .{});
        try interface.blank();

        std.process.exit(1);
    } orelse {
        try interface.log(.Error, "Cannot find the difficulty.", .{});
        try interface.blank();

        std.process.exit(1);
    };

    return difficulty;
}

// Initialize the surface.
pub fn initSurface(interface: *Interface, allocator: std.mem.Allocator) !Surface {
    const backend = interface.getOption("backend", "opengl");
    const threads = interface.parseOption(u8, "threads", @as(u8, @intCast(try std.Thread.getCpuCount())));
    const width = interface.parseOption(u16, "width", 1280);
    const height = interface.parseOption(u16, "height", 720);

    if (std.mem.eql(u8, backend, "basic")) {
        return Surface.init(.Basic, width, height, threads, allocator);
    } else if (std.mem.eql(u8, backend, "opengl")) {
        return Surface.init(.OpenGL, width, height, threads, allocator);
    } else {
        try interface.log(.Error, "Unknown backend: \"{s}\"", .{backend});
        try interface.blank();

        std.process.exit(1);
    }
}
