const std = @import("std");

const Beatmap = @This();

allocator: std.mem.Allocator,
difficulties: std.StringArrayHashMap([]u8),
resources:  std.StringArrayHashMap([]u8),

// The difficulty.
pub const Difficulty = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,

    fields: std.StringArrayHashMap([]const u8),
    objects: std.ArrayList([]const u8),

    // Initialize a difficulty.
    pub fn init(buffer: []const u8, allocator: std.mem.Allocator) !Difficulty {
        const data = try allocator.alloc(u8, buffer.len);
        @memcpy(data, buffer);

        var fields = std.StringArrayHashMap([]const u8).init(allocator);
        var objects = std.ArrayList([]const u8).init(allocator);

        var iterator = std.mem.tokenizeAny(u8, data, "\r\n");
        var current_section = @as(?[]const u8, null);

        while (iterator.next()) |line| {
            if (line.len > 0 and (line[0] == '[' and line[line.len - 1] == ']')) {
                current_section = line[1..line.len - 1];
            } else if (current_section != null) {
                if (std.mem.eql(u8, current_section.?, "HitObjects")) {
                    try objects.append(line);
                } else if (std.mem.indexOfScalar(u8, line, '=')) |separator_index| {
                    const name = try std.mem.concat(allocator, u8, &.{current_section.?, line[0..separator_index]});
                    const value = line[separator_index + 1..];

                    try fields.put(name, value);
                }
            }
        }

        return Difficulty{
            .allocator = allocator,
            .buffer = data,

            .fields = fields,
            .objects = objects
        };
    }

    // Deinitialize the difficulty.
    pub fn deinit(self: *Difficulty) void {
        self.allocator.free(self.buffer);

        self.fields.deinit();
        self.objects.deinit();
    }
};

// Initialize a beatmap from a file.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Beatmap {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator); 
}

// Initialize a beatmap from the memory.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Beatmap {
    var buffer_stream = std.io.fixedBufferStream(buffer);
    var seekable_stream = buffer_stream.seekableStream();

    var iterator = try std.zip.Iterator(@TypeOf(seekable_stream)).init(seekable_stream);  
    var difficulties = std.StringArrayHashMap([]u8).init(allocator);
    var resources = std.StringArrayHashMap([]u8).init(allocator);

    while (try iterator.next()) |entry| {
        try seekable_stream.seekTo(entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));

        const filename = try allocator.alloc(u8, entry.filename_len);
        const read_bytes = try seekable_stream.context.reader().readAll(filename);

        if (read_bytes != filename.len) {
            return error.ZipBadFileOffset;
        }

        try seekable_stream.seekTo(entry.file_offset);

        const local_header = try seekable_stream.context.reader().readStructEndian(std.zip.LocalFileHeader, .little);
        const local_data_header_offset = @as(u64, local_header.filename_len) + @as(u64, local_header.extra_len);
        const local_data_file_offset = @as(u64, entry.file_offset) + @as(u64, @sizeOf(std.zip.LocalFileHeader)) + local_data_header_offset;

        try seekable_stream.seekTo(local_data_file_offset);

        var stoarge = std.ArrayList(u8).init(allocator);
        defer stoarge.deinit();

        _ = try std.zip.decompress(
            entry.compression_method,
            entry.uncompressed_size,
            @constCast(&std.io.limitedReader(seekable_stream.context.reader(), entry.compressed_size)).reader(),
            stoarge.writer(),
        );

        const file_data = try allocator.alloc(u8, stoarge.items.len);
        @memcpy(file_data, stoarge.items);

        if (std.mem.containsAtLeast(u8, filename, 1, ".") and std.mem.eql(u8, filename[std.mem.lastIndexOfScalar(u8, filename, '.').?..], ".osu")) {
            try difficulties.put(filename, file_data);
        } else {
            try resources.put(filename, file_data);
        }
    }

    return Beatmap{
        .allocator = allocator,
        .difficulties = difficulties,
        .resources = resources
    };
}

// Deinitialize the beatmap.
pub fn deinit(self: *Beatmap) void {
    var difficulty_iterator = self.difficulties.iterator();
    var resource_iterator = self.resources.iterator();

    while (difficulty_iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }

    while (resource_iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }

    self.difficulties.deinit();
    self.resources.deinit();
}

// Get a difficulty.
pub fn getDifficulty(self: *Beatmap, filename: []const u8, allocator: std.mem.Allocator) !?Difficulty {
    if (self.difficulties.contains(filename)) {
        return try Difficulty.init(self.difficulties.get(filename, allocator).?);
    }

    return null;
}

// Find a difficulty.
pub fn findDifficulty(self: *Beatmap, hash: []const u8, allocator: std.mem.Allocator) !?Difficulty {
    var iterator = self.difficulties.iterator();
    var buffer = @as([16]u8, undefined);

    while (iterator.next()) |entry| {
        std.crypto.hash.Md5.hash(entry.value_ptr.*, &buffer, .{}); 

        if (std.mem.eql(u8, &std.fmt.bytesToHex(buffer, .lower), hash)) {
            return try Difficulty.init(entry.value_ptr.*, allocator);
        }
    }

    return null;
}

// Get a resource.
pub fn getResource(self: *Beatmap, filename: []const u8) ?[]u8 {
    return self.resources.get(filename);
}
