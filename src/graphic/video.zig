const std = @import("std");

// The encoder.
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,

    fps: u16,
    width: u16,
    height: u16,
    
    arguments: struct {
        ffmpeg: []const u8,
        filename: []const u8,
        resolution: []const u8,
        fps: []const u8,
        threads: []const u8,
    },

    // The options.
    pub const Options = struct {
        fps: u8,
        width: u16,
        height: u16,

        ffmpeg: []const u8 = "ffmpeg",
        threads: u8 = 1
    };

    // Initialize an encoder.
    pub fn init(filename: []const u8, options: Encoder.Options, allocator: std.mem.Allocator) !Encoder {
        const ffmpeg_buffer = try allocator.dupe(u8, options.ffmpeg);
        errdefer allocator.free(ffmpeg_buffer);

        const filename_buffer = try allocator.dupe(u8, filename);
        errdefer allocator.free(filename_buffer);

        const resolution_buffer = try std.fmt.allocPrint(allocator, "{}x{}", .{options.width, options.height});
        errdefer allocator.free(resolution_buffer);

        const fps_buffer = try std.fmt.allocPrint(allocator, "{}", .{options.fps});
        errdefer allocator.free(resolution_buffer);

        const threads_buffer = try std.fmt.allocPrint(allocator, "{}", .{options.threads});
        errdefer allocator.free(threads_buffer);

        var process = std.process.Child.init(&.{
            ffmpeg_buffer, "-y",
            "-f", "rawvideo",
            "-pix_fmt", "rgb24",
            "-s", resolution_buffer,
            "-r", fps_buffer,
            "-i", "-",
            "-vcodec", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "veryfast",
            "-threads", threads_buffer,
            filename_buffer
        }, allocator);

        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        _ = try process.spawn();

        return Encoder{
            .allocator = allocator,
            .process = process,

            .fps = options.fps,
            .width = options.width,
            .height = options.height,

            .arguments = .{
                .ffmpeg = ffmpeg_buffer,
                .filename = filename_buffer,
                .resolution = resolution_buffer,
                .fps = fps_buffer,
                .threads = threads_buffer
            }
        };
    }

    // Deinitialize the encoder.
    pub fn deinit(self: *Encoder) void {
        self.allocator.free(self.arguments.ffmpeg);
        self.allocator.free(self.arguments.filename);
        self.allocator.free(self.arguments.resolution);
        self.allocator.free(self.arguments.fps);
        self.allocator.free(self.arguments.threads);
    }

    // Add a frame to the video.
    pub fn addFrame(self: *Encoder, buffer: []u8) !void {
        if (buffer.len != (@as(u64, @intCast(self.width)) * self.height) * 3) {
            return error.InvalidBufferLength;
        }

        _ = try self.process.stdin.?.write(buffer);
    }

    // Finalize the video.
    pub fn finalize(self: *Encoder) !void {
        self.process.stdin.?.close();
        self.process.stdin = null;

        _ = try self.process.wait();
    }
};

// The audio writer.
pub const AudioWriter = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,

    arguments: struct {
        ffmpeg: []const u8,
        filename: []const u8,
        offset: []const u8,
        threads: []const u8,
    },

    // The options.
    pub const Options = struct {
        ffmpeg: []const u8 = "ffmpeg",
        threads: u8 = 1
    };

    // Initialize an audio writer.
    pub fn init(filename: []const u8, offset: u64, options: AudioWriter.Options, allocator: std.mem.Allocator) !AudioWriter {
        const ffmpeg_buffer = try allocator.dupe(u8, options.ffmpeg);
        errdefer allocator.free(ffmpeg_buffer);

        const filename_buffer = try allocator.dupe(u8, filename);
        errdefer allocator.free(filename_buffer);

        const offset_buffer = try std.fmt.allocPrint(allocator, "{d}", .{@as(f32, @floatFromInt(offset)) / 1000});
        errdefer allocator.free(offset_buffer);

        const threads_buffer = try std.fmt.allocPrint(allocator, "{}", .{options.threads});
        errdefer allocator.free(threads_buffer);

        var process = std.process.Child.init(&.{
            ffmpeg_buffer, "-y",
            "-i", filename_buffer,
            "-itsoffset", offset_buffer,
            "-i", "-",
            "-threads", threads_buffer,
            filename_buffer
        }, allocator);

        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        _ = try process.spawn();

        return AudioWriter{
            .allocator = allocator,
            .process = process,

            .arguments = .{
                .ffmpeg = ffmpeg_buffer,
                .filename = filename_buffer,
                .offset = offset_buffer,
                .threads = threads_buffer
            }
        };
    }

    // Deinitialize the audio witer.
    pub fn deinit(self: *AudioWriter) void {
        self.allocator.free(self.arguments.ffmpeg);
        self.allocator.free(self.arguments.filename);
        self.allocator.free(self.arguments.offset);
        self.allocator.free(self.arguments.threads);
    }

    // Write an audio to a video.
    pub fn write(self: *AudioWriter, buffer: []u8) !void {
        _ = try self.process.stdin.?.write(buffer);
    }

    // Finalize the video.
    pub fn finalize(self: *AudioWriter) !void {
        self.process.stdin.?.close();
        self.process.stdin = null;

        _ = try self.process.wait();
    }
};
