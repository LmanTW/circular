const std = @import("std");

// Define a thread pool.
pub fn define(comptime T: type) type {
    return struct{
        const Threads = @This();

        allocator: std.mem.Allocator,
        threads: std.ArrayList(std.Thread),
    
        range: [2]T,
        chunk_size: T,
    
        // Initialize a thread pool.
        pub fn init(amount: u8, range: [2]T, allocator: std.mem.Allocator) Threads {
            return Threads{
                .allocator = allocator,
                .threads = std.ArrayList(std.Thread).init(allocator),
        
                .range = range,
                .chunk_size = switch (T) {
                    u8 => @as(T, @intFromFloat(@ceil(@as(f32, @floatFromInt(range[1] - range[0])) / @as(f32, @floatFromInt(amount))))),
                    u16 => @as(u16, @intFromFloat(@ceil(@as(f32, @floatFromInt(range[1] - range[0])) / @as(f32, @floatFromInt(amount))))),
                    u32 => @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(range[1] - range[0])) / @as(f32, @floatFromInt(amount))))),
                    u64 => @as(T, @intFromFloat(@ceil(@as(f32, @floatFromInt(range[1] - range[0])) / @as(f32, @floatFromInt(amount))))),
                    f32 => @ceil((range[1] - range[0]) / @as(f32, @floatFromInt(amount))),
                    f64 => @ceil((range[1] - range[0]) / @as(f32, @floatFromInt(amount))),
                    else => @compileError("Unsupported range type: " ++ @typeName(T))
                }
            };
        }
        
        // Deinitialize the thread pool.
        pub fn deinit(self: *Threads) void {
            self.threads.deinit();
        }
        
        // Spawn the threads.
        pub fn spawn(self: *Threads, ctx: anytype, comptime function: anytype) !void {
            var chunk_start = self.range[0];

            while (chunk_start < self.range[1]) {
                try self.threads.append(try std.Thread.spawn(.{}, function, .{ctx, .{chunk_start, @min(chunk_start + self.chunk_size, self.range[1])}}));

                chunk_start += self.chunk_size;
            }

            for (self.threads.items) |thread| {
                thread.join();
            }
        } 
    };
}
