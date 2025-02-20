const std = @import("std");

const Replay = @This();

allocator: std.mem.Allocator,
reader: Reader,

version: u32,
ruleset: Ruleset,
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
mod_info: u16,
frames: []Frame,
life_graph: []const u8,
timestamp: u64,

// The ruleset.
pub const Ruleset = enum(u4) {
    Standard,
    Taiko,
    Catch,
    Mania
};

// The frame.
pub const Frame = struct {
    w: i32,
    x: f32,
    y: f32,
    z: u32
};

// Initialize a replay from a file.
// > [file] is no longer required after initializaion.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Replay {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator);
}

// Initialize a replay from the memory.
// > [buffer] is no longer required after initializaion.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Replay {
    var reader = Reader.init(buffer, allocator);
    errdefer reader.deinit();

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
    const mod_info = reader.readShort() catch 0;

    if (compressed_data.len < 13) {
        return error.CorruptInput;
    }

    var decompress = try std.compress.lzma.decompress(allocator, @constCast(&std.io.fixedBufferStream(compressed_data)).reader());
    defer decompress.deinit();

    // Read the LZMA header to get the decompressed size.
    //
    // 0      | LZMA model properties (lc, lp, pb) in encoded form.
    // 1 ~ 4  | Dictionary size (u32, little-endian).
    // 5 ~ 13 | Uncompressed size (u64, little-endian).

    const decompressed_data = try allocator.alloc(u8, std.mem.readInt(u64, compressed_data[5..13], .little));
    defer allocator.free(decompressed_data);

    var offset = @as(u64, 0);

    while (true) {
        const bytes_read = try decompress.read(decompressed_data[offset..]);

        if (bytes_read == 0) {
            break;
        }

        offset += bytes_read;
    }

    var frame_iterator = std.mem.splitAny(u8, decompressed_data, ",");
    var frames = std.ArrayList(Frame).init(allocator);
    errdefer frames.deinit();

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

            if (!std.mem.eql(u8, w.?, "-12345")) {
                try frames.append(.{
                    .w = try std.fmt.parseInt(i32, w.?, 10),
                    .x = try std.fmt.parseFloat(f32, x.?),
                    .y = try std.fmt.parseFloat(f32, y.?),
                    .z = try std.fmt.parseInt(u32, z.?, 10)
                });
            }
        }
    }

    return Replay{
        .allocator = allocator,
        .reader = reader,

        .version = version,
        .ruleset = @as(Ruleset, @enumFromInt(ruleset)),
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
        .mod_info = mod_info,
        .frames = try frames.toOwnedSlice(),
        .life_graph = life_graph,
        .timestamp = timestamp
    };
}

// Deinitialize the replay.
pub fn deinit(self: *Replay) void {
    self.reader.deinit();
    self.allocator.free(self.frames);
}

// The replay reader.
pub const Reader = struct {
    allocator: std.mem.Allocator,
    storage: std.ArrayList([]const u8),

    buffer: []u8,
    index: usize,

    // Initialize a reader.
    pub fn init(buffer: []u8, allocator: std.mem.Allocator) Reader {
        return Reader{
            .allocator = allocator,
            .storage = std.ArrayList([]const u8).init(allocator),

            .buffer = buffer,
            .index = 0
        };
    }

    // Deinitialize the reader.
    pub fn deinit(self: *Reader) void {
        for (self.storage.items) |item| {
            self.allocator.free(item);
        }

        self.storage.deinit();
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
            shift += 7;
            
            if ((byte & 0x80) == 0)
                return value;
            if (shift >= @sizeOf(usize) * 8) 
                return error.Overflow;
        }

        return error.Incomplete;
    }

    // Read a "String".
    pub fn readString(self: *Reader) ![]const u8 {
        if (try self.readByte() == 0x0b) {
            const buffer = try self.allocator.dupe(u8, try self.read(try self.readULEB128()));

            // The string is owned by the reader so we need to keep a record of it.
            try self.storage.append(buffer);

            return buffer;
        }

        return "";
    }
};
