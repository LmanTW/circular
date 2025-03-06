const std = @import("std");

// The encoder.
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,

    fps: u16,
    width: u16,
    height: u16,
    
    arguments: struct {
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
        const filename_buffer = try allocator.alloc(u8, filename.len);
        errdefer allocator.free(filename_buffer);

        const resolution_buffer = try std.fmt.allocPrint(allocator, "{}x{}", .{options.width, options.height});
        errdefer allocator.free(resolution_buffer);

        const fps_buffer = try std.fmt.allocPrint(allocator, "{}", .{options.fps});
        errdefer allocator.free(resolution_buffer);

        const threads_buffer = try std.fmt.allocPrint(allocator, "{}", .{options.threads});
        errdefer allocator.free(threads_buffer);

        @memcpy(filename_buffer, filename);

        var process = std.process.Child.init(&.{
            options.ffmpeg, "-y",
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
                .filename = filename_buffer,
                .resolution = resolution_buffer,
                .fps = fps_buffer,
                .threads = threads_buffer
            }
        };
    }

    // Deinitialize the encoder.
    pub fn deinit(self: *Encoder) void {
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
