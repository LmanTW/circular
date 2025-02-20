const options = @import("options");
const std = @import("std");

pub const Beatmap = @import("./game/formats/Beatmap.zig");
pub const Replay = @import("./game/formats/Replay.zig");
pub const Skin = @import("./game/formats/Skin.zig");

const Surface = @import("./graphic/Surface.zig");
const Replayer = @import("./game/Replayer.zig");
const Interface = @import("./Interface.zig");
const Color = @import("./graphic/Color.zig");
const Storage = @import("./Storage.zig");

// The main function :3
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Yes sir, your allocator.
    const allocator = gpa.allocator();

    var application = try Application.init(allocator);
    defer application.deinit();

    if (application.interface.countArguments() > 0) {
        application.interface.blank();
        application.interface.log(.Running, "Loading the replay...", .{});

        var replay = try application.loadReplay(application.interface.getArgument(0));
        defer replay.deinit();

        application.interface.log(.Complete, "Successfully loaded the replay!", .{});
        application.interface.log(.Running, "Loading the beatmap...", .{});

        var beatmap = try application.loadBeatmap(&replay);
        defer beatmap.deinit();

        application.interface.log(.Complete, "Successfully loaded the beatmap!", .{});
        application.interface.log(.Running, "Loading the difficulty...", .{});

        var difficulty = try application.loadDifficulty(&beatmap, replay.beatmap_hash);
        defer difficulty.deinit();

        application.interface.log(.Complete, "Successfully loaded the difficulty!", .{});
        application.interface.log(.Running, "Loading the skin...", .{});

        var skin = try application.loadSkin(application.options.skin);
        defer skin.deinit();

        application.interface.log(.Complete, "Successfully loaded the skin!", .{});
        application.interface.log(.Running, "Initializing the renderer...", .{});

        var surface = try application.initSurface();
        defer surface.deinit();

        application.interface.log(.Complete, "Successfully initialized the renderer!", .{});
        application.interface.log(.Running, "Initializing the replayer...", .{});

        var replayer = try application.initReplayer(replay.ruleset);
        defer replayer.deinit();

        try replayer.loadDifficulty(&difficulty);
        try replayer.loadReplay(&replay);

        application.interface.log(.Complete, "Successfully initialized the replayer!", .{});
        application.interface.blank();
    } else {
        application.interface.write(
            \\
            \\ Circular (v0.1)
            \\   - The lightweight osu! replay renderer.
            \\
            \\ Usage:
            \\   circular [...options] [*.osr]
            \\
            \\ Options:
            \\   output="replay.mp4"  | The filename of the output video.
            \\
            \\   log.format="verbose" | The logging format. ("none", "verbose", "json")
            \\   log.level="info"     | The logging level. ("info", "debug")
            \\
            \\   video.fps=30         | The frame rate of the video.
            \\   video.width=1280     | The width of the video.
            \\   video.height=720     | The height of the video.
            \\
            \\   skin="default"       | The filename of the skin to use.
            \\
            \\   ffmpeg="ffmpeg"      | The command/path to ffmpeg.
            \\   backend="opengl"     | The rendering backend. ("basic", "opengl")
            \\   threads="auto"       | The amount CPU threads to use.
            \\
            \\
        );
    }
}

// The application.
const Application = struct {
    allocator: std.mem.Allocator,
    interface: Interface,

    options: struct {
        output: []const u8,

        fps: u8,
        width: u16,
        height: u16,

        skin: []const u8,

        backend: []const u8,
        threads: u8,

        ffmpeg: []const u8
    },

    // Initialize an application
    pub fn init(allocator: std.mem.Allocator) !Application {
        var interface = try Interface.init(allocator);

        return Application{
            .allocator = allocator,
            .interface = interface,

            .options = .{
                .output = interface.getOption("output", "replay.mp4"),

                .fps = interface.parseOptionRange(u8, "video.fps", 1, null, 30),
                .width = interface.parseOptionRange(u16, "video.width", 1, null, 1280),
                .height = interface.parseOptionRange(u16, "video.height", 1, null, 720),

                .skin = interface.getOption("skin", "default"),

                .ffmpeg = interface.getOption("ffmpeg", "ffmpeg"),
                .backend = interface.getOption("backend", "opengl"),
                .threads = interface.parseOptionRange(u8, "threads", 1, null, @as(u8, @intCast(try std.Thread.getCpuCount())))
            }
        };
    }

    // Deinitialize the application
    pub fn deinit(self: *Application) void {
        self.interface.deinit();
    }
    
    // Load the replay.
    pub fn loadReplay(self: *Application, filename: []const u8) !Replay { 
        const file = std.fs.cwd().openFile(filename, .{}) catch {
            const current_path = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            const absolute_path = try std.fs.path.resolve(self.allocator, &.{current_path, filename});
            defer self.allocator.free(current_path);
            defer self.allocator.free(absolute_path);

            self.interface.log(.Error, "Failed to open the file: \"{s}\"", .{absolute_path});
            self.interface.blank();

            std.process.exit(1);
        };
        defer file.close();

        const buffer = try self.allocator.alloc(u8, try file.getEndPos());
        defer self.allocator.free(buffer);

        _ = try file.readAll(buffer);

       return Replay.initFromMemory(buffer, self.allocator) catch {
            self.interface.log(.Error, "Failed to load the replay.", .{});
            self.interface.blank();

            std.process.exit(1);
        };
    }

    // Load the beatmap.
    pub fn loadBeatmap(self: *Application, replay: *Replay) !Beatmap {
        var storage = try Storage.init(self.allocator);
        defer storage.deinit();

        if (!try storage.checkBeatmap(replay.beatmap_hash)) {
            self.interface.log(.Progress, "Downloading the beatmap...", .{});
            self.interface.log(.Info, "Currently using Mino to download the beatmap.", .{});
            self.interface.log(.Info, "Check out their awesome service: \"https://catboy.best\"", .{});

            storage.downlaodBeatmap(replay.beatmap_hash) catch {
                self.interface.log(.Error, "Failed to download the beatmap.", .{});
                self.interface.blank();

                std.process.exit(1);
            };

            self.interface.log(.Progress, "Clearing the cache...", .{});

            try storage.clean();
        }

        const buffer = try storage.readBeatmap(replay.beatmap_hash, self.allocator);
        defer self.allocator.free(buffer);

        return Beatmap.initFromMemory(buffer, self.allocator) catch {
           self.interface.log(.Error, "Failed to load the beatmap.", .{});
           self.interface.blank();

           std.process.exit(1);
        };
    }

    // Load the difficulty.
    pub fn loadDifficulty(self: *Application, beatmap: *Beatmap, hash: []const u8) !Beatmap.Difficulty {
       const filename = beatmap.findDifficulty(hash) orelse {
           self.interface.log(.Error, "Difficulty not found.", .{});
           self.interface.blank();

           std.process.exit(1);
       };

       return (beatmap.getDifficulty(filename, self.allocator) catch {
            self.interface.log(.Error, "Failed to load the difficulty.", .{});
            self.interface.blank();

            std.process.exit(1);
        }).?; 
    }

    // Load the skin.
    pub fn loadSkin(self: *Application, filename: []const u8) !Skin {
        const file = std.fs.cwd().openFile(filename, .{}) catch {
            const current_path = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            const absolute_path = try std.fs.path.resolve(self.allocator, &.{current_path, filename});
            defer self.allocator.free(current_path);
            defer self.allocator.free(absolute_path);

            self.interface.log(.Error, "Failed to open the file: \"{s}\"", .{absolute_path});
            self.interface.blank();

            std.process.exit(1);
        };
        defer file.close();

        const buffer = try self.allocator.alloc(u8, try file.getEndPos());
        defer self.allocator.free(buffer);

        _ = try file.readAll(buffer);

        return Skin.initFromMemory(buffer, self.allocator) catch {
            self.interface.log(.Error, "Failed to load the skin.", .{});
            self.interface.blank();

            std.process.exit(1);
        };
    }

    // Initialize the surface.
    pub fn initSurface(self: *Application) !Surface {
        var backend = @as(Surface.Backend, undefined);

        if (std.mem.eql(u8, self.options.backend, "basic"))
            backend = .Basic;
        if (std.mem.eql(u8, self.options.backend, "opengl"))
            backend = .OpenGL;

        self.interface.log(.Debug, "Basic:  {s}", .{if (options.backend_basic) "Available" else "Unavailable"});
        self.interface.log(.Debug, "OpenGL: {s}", .{if (options.backend_opengl) "Available" else "Unavailable"});

        return Surface.init(backend, self.options.width, self.options.height, self.options.threads, self.allocator) catch {
            self.interface.log(.Error, "Failed to initialize the renderer.", .{});
            self.interface.blank();

            std.process.exit(1);
        };
    }

    // Initialize the replayer.
    pub fn initReplayer(self: *Application, ruleset: Replay.Ruleset) !Replayer {
        switch (ruleset) {
            .Mania => return try Replayer.init(.Mania, self.allocator),

            else => {
                self.interface.log(.Error, "Unsupported ruleset: \"{s}\"", .{@tagName(ruleset)});
                self.interface.blank();

                std.process.exit(1);
            }
        }
    }
};
