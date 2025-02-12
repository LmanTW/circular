const std = @import("std");

const Replay = @This();

allocator: std.mem.Allocator,
reader: Reader,

ruleset: Ruleset,
version: u32,
score_id: u64,
beatmap_hash: []const u8,
replay_hash: []const u8,
player_name: []const u8,
total_score: u32,
best_combo: u16,
perfect: bool,
hit_1: u16,
hit_2: u16,
hit_3: u16,
hit_4: u16,
hit_5: u16,
misses: u16,
mods: u64,
extra_mod_info: u16,
timestamp: u64,
life_graph: []const u8,
frames: std.ArrayList(Frame),

// The ruleset.
pub const Ruleset = enum(u4) {
    Standard,
    Taiko,
    Catch,
    Mania
};

// The frame data.
pub const Frame = packed struct {
    w: i16,
    x: f32,
    y: f32,
    z: u32
};

// Initialize a replay from a file.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Replay {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator);
}

// Initialize a replay from the memory.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Replay {
    var reader = Reader.init(buffer, allocator);

    const ruleset =  try reader.readByte();
    const version = try reader.readInteger();
    const beatmap_hash = try reader.readString();
    const player_name = try reader.readString();
    const replay_hash = try reader.readString();
    const hit_1 = try reader.readShort();
    const hit_2 = try reader.readShort();
    const hit_3 = try reader.readShort();
    const hit_4 = try reader.readShort();
    const hit_5 = try reader.readShort();
    const misses = try reader.readShort();
    const total_score = try reader.readInteger();
    const best_combo = try reader.readShort();
    const perfect = try reader.readByte() == 1;
    const mods = try reader.readInteger();
    const life_graph = try reader.readString();
    const timestamp = try reader.readLong();
    const compressed_length = try reader.readInteger();
    const compressed_data = try reader.read(compressed_length);
    const score_id = try reader.readLong();
    const extra_mod_info = reader.readShort() catch 0;

    var decompress = try std.compress.lzma.decompress(allocator, @constCast(&std.io.fixedBufferStream(compressed_data)).reader());
    defer decompress.deinit();

    var stoarge = std.ArrayList(u8).init(allocator);
    var chunk = try allocator.alloc(u8, 4096);
    defer stoarge.deinit();
    defer allocator.free(chunk);

    while (true) {
        const bytes_read = try decompress.reader().read(chunk);

        if (bytes_read == 0) {
            break;
        }

        try stoarge.appendSlice(chunk[0..bytes_read]);
    }

    var frame_iterator = std.mem.splitAny(u8, stoarge.items, ",");
    var frames = std.ArrayList(Frame).init(allocator);

    while (frame_iterator.next()) |frame| {
        if (frame.len > 0) {
            var part_iterator = std.mem.splitAny(u8, frame, "|");

            const w = part_iterator.next();
            const x = part_iterator.next();
            const y = part_iterator.next();
            const z = part_iterator.next();

            if (w == null or x == null or y == null or z == null) {
                return error.IncompleteFrame;
            }

            try frames.append(.{
                .w = try std.fmt.parseInt(i16, w.?, 10),
                .x = try std.fmt.parseFloat(f32, x.?),
                .y = try std.fmt.parseFloat(f32, y.?),
                .z = try std.fmt.parseInt(u32, z.?, 10)
            });
        } 
    }

    return Replay{
        .allocator = allocator,
        .reader = reader,

        .ruleset = @as(Ruleset, @enumFromInt(ruleset)),
        .version = version,
        .score_id = score_id,
        .beatmap_hash = beatmap_hash,
        .replay_hash = replay_hash,
        .player_name = player_name,
        .total_score = total_score,
        .best_combo = best_combo,
        .perfect = perfect,
        .hit_1 = hit_1,
        .hit_2 = hit_2,
        .hit_3 = hit_3,
        .hit_4 = hit_4,
        .hit_5 = hit_5,
        .misses = misses,
        .mods = mods,
        .extra_mod_info = extra_mod_info,
        .timestamp = timestamp,
        .life_graph = life_graph,
        .frames = frames
    };
}

// Deinitialize the replay.
pub fn deinit(self: *Replay) void {
    self.reader.deinit();
    self.frames.deinit();
}

// Get the length of the replay.
pub fn getLength(self: *Replay) u64 {
    var length = @as(i64, 0);

    for (self.frames.items) |frame| {
        length += frame.w;
    }

    return @as(u64, @intCast(length));
}

// The replay reader.
pub const Reader = struct {
    index: usize,
    buffer: []u8,

    allocator: std.mem.Allocator,
    stoarge: std.ArrayList([]const u8),

    // Initialize a reader.
    pub fn init(buffer: []u8, allocator: std.mem.Allocator) Reader {
        return Reader{
            .index = 0,
            .buffer = buffer,

            .allocator = allocator,
            .stoarge = std.ArrayList([]const u8).init(allocator)
        };
    }

    // Deinitialize the reader.
    pub fn deinit(self: *Reader) void {
        for (self.stoarge.items) |item| {
            self.allocator.free(item);
        }

        self.stoarge.deinit();
    }

    // Read specified amount of bytes.
    pub fn read(self: *Reader, length: usize) ![]u8 {
        if (self.index + length > self.buffer.len) {
            return error.OutOfBound;
        }

        const bytes = self.buffer[self.index..self.index + length];
        self.index += length;

        return bytes;
    }

    // Read a "Byte".
    pub fn readByte(self: *Reader) !u8 {
        return std.mem.readInt(u8, @as(*[1]u8, @ptrCast(try self.read(1))), .little);
    }

    // Read a "Short".
    pub fn readShort(self: *Reader) !u16 {
        return std.mem.readInt(u16, @as(*[2]u8, @ptrCast(try self.read(2))), .little);
    }

    // Read a "Integer".
    pub fn readInteger(self: *Reader) !u32 {
        return std.mem.readInt(u32, @as(*[4]u8, @ptrCast(try self.read(4))), .little);
    }

    // Read a "Long".
    pub fn readLong(self: *Reader) !u64 {
        return std.mem.readInt(u64, @as(*[8]u8, @ptrCast(try self.read(8))), .little);
    }

    // Read a "ULEB128".
    pub fn readULEB128(self: *Reader) !usize {
        var value: usize = 0;
        var shift: usize = 0;

        while (true) {
            const byte = try self.readByte();

            value |= @as(usize, @intCast(byte & 0x7F)) << @as(std.math.Log2Int(usize), @intCast(shift));
            
            if ((byte & 0x80) == 0) {
                return value;
            }

            shift += 7;

            if (shift >= @sizeOf(usize) * 8) {
                return error.Overflow;
            }
        }

        return error.Incomplete;
    }

    // Read a "String".
    pub fn readString(self: *Reader) ![]const u8 {
        if (try self.readByte() == 0x0b) {
            const length = try self.readULEB128();

            const buffer = try self.allocator.alloc(u8, length);
            @memcpy(buffer, try self.read(length));

            try self.stoarge.append(buffer);

            return buffer;
        }

        return "";
    }
};
