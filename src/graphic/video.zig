const std = @import("std");

// The encoder.
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,

    width: u16,
    height: u16,
    
    filename: []const u8,
    resolution: []const u8,

    // Initialize an encoder.
    pub fn init(filename: []const u8, width: u16, height: u16, ffmpeg: []const u8, allocator: std.mem.Allocator) !Encoder {
        const resolution = try std.fmt.allocPrint(allocator, "{}x{}", .{width, height});

        const filename_buffer = try allocator.alloc(u8, filename.len);
        @memcpy(filename_buffer, filename);

        var process = std.process.Child.init(&.{
            ffmpeg, "-y",
            "-f", "rawvideo",
            "-pix_fmt", "rgb24",
            "-s", resolution,
            "-r", "60",
            "-i", "-",
            "-vcodec", "libx264",
            "-pix_fmt", "yuv420p",
            filename_buffer
        }, allocator);

        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        _ = try process.spawn();

        return Encoder{
            .allocator = allocator,
            .process = process,

            .width = width,
            .height = height,

            .filename = filename_buffer,
            .resolution = resolution
        };
    }

    // Deinitialize the encoder.
    pub fn deinit(self: *Encoder) void {
        self.allocator.free(self.filename);
        self.allocator.free(self.resolution);
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
