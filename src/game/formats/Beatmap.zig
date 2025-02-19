const std = @import("std");

const Beatmap = @This();

allocator: std.mem.Allocator,
difficulties: std.StringHashMap([]u8),
resources: std.StringHashMap([]u8),

// Initialize a beatmap from a file.
// > [file] is no longer required after initializaion.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Beatmap {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator);
}

// Initialize a beatmap from the memory.
// > [buffer] is no longer required after initializaion.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Beatmap {
    var buffer_stream = std.io.fixedBufferStream(buffer);
    var seekable_stream = buffer_stream.seekableStream();
    var reader = seekable_stream.context.reader();

    var difficulties = std.StringHashMap([]u8).init(allocator);
    var resources = std.StringHashMap([]u8).init(allocator);

    errdefer {
        var difficulty_iterator = difficulties.iterator();
        var resource_iterator = resources.iterator();

        while (difficulty_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }

        while (resource_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }

        difficulties.deinit();
        resources.deinit();
    }

    var entry_iterator = try std.zip.Iterator(@TypeOf(seekable_stream)).init(seekable_stream);

    while (try entry_iterator.next()) |entry| {
        try seekable_stream.seekTo(entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));

        const filename = try allocator.alloc(u8, entry.filename_len);
        const content = try allocator.alloc(u8, entry.uncompressed_size);

        if (try reader.readAll(filename) != filename.len) {
            return error.BadFileOffset;
        }

        try seekable_stream.seekTo(entry.file_offset);

        const local_header = try reader.readStructEndian(std.zip.LocalFileHeader, .little);
        const local_header_offset = @as(u64, local_header.filename_len) + @as(u64, local_header.extra_len);
        const local_file_offset = @as(u64, entry.file_offset) + @as(u64, @sizeOf(std.zip.LocalFileHeader)) + local_header_offset;

        try seekable_stream.seekTo(local_file_offset);

        _ = try std.zip.decompress(
            entry.compression_method,
            entry.uncompressed_size,
            @constCast(&std.io.limitedReader(reader, entry.compressed_size)).reader(),
            @constCast(&std.io.fixedBufferStream(content)).writer()
        );

        if (std.mem.containsAtLeast(u8, filename, 1, ".") and std.mem.eql(u8, filename[std.mem.lastIndexOfScalar(u8, filename, '.').?..], ".osu")) {
            try difficulties.put(filename, content);
        } else {
            try resources.put(filename, content);
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
        return try Difficulty.initFromMemory(self.difficulties.get(filename).?, allocator);
    }

    return null;
}

// Find a difficulty.
pub fn findDifficulty(self: *Beatmap, hash: []const u8) ?[]const u8 {
    var difficulty_iterator = self.difficulties.iterator();
    var buffer = @as([16]u8, undefined);

    while (difficulty_iterator.next()) |entry| {
        std.crypto.hash.Md5.hash(entry.value_ptr.*, &buffer, .{}); 

        if (std.mem.eql(u8, &std.fmt.bytesToHex(buffer, .lower), hash)) {
            return entry.key_ptr.*;
        }
    }

    return null;
}

// The difficulty.
pub const Difficulty = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,

    fields: std.StringHashMap([]const u8),
    objects: [][]const u8,

    // Initialize a difficulty from a file.
    // > [file] is no longer required after initializaion.
    pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Difficulty {
        const buffer = try allocator.alloc(u8, try file.getEndPos());
        defer allocator.free(buffer);

        _ = try file.readAll(buffer);

        return try Difficulty.initFromMemory(buffer, allocator);
    }

    // Initialize a difficulty from the memory.
    // > [buffer] is no longer required after initializaion.
    pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Difficulty {
        const owned_buffer = try allocator.dupe(u8, buffer);

        var fields = std.StringHashMap([]const u8).init(allocator);
        var objects = std.ArrayList([]const u8).init(allocator);

        errdefer {
            var field_iterator = fields.iterator();

            while (field_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }

            fields.deinit();
            objects.deinit();

            allocator.free(owned_buffer);
        }

        var line_iterator = std.mem.tokenizeAny(u8, owned_buffer, "\r\n");
        var current_section = @as(?[]const u8, null);

        while (line_iterator.next()) |line| {
            if (line.len > 0 and (line[0] == '[' and line[line.len - 1] == ']')) {
                current_section = line[1..line.len - 1];
            } else if (current_section != null) {
                if (std.mem.eql(u8, current_section.?, "HitObjects")) {
                    try objects.append(line);
                } else if (std.mem.indexOfScalar(u8, line, ':')) |separator_index| {
                    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{current_section.?, std.mem.trim(u8, line[0..separator_index], " ")});
                    errdefer allocator.free(name);

                    if (fields.contains(name)) {
                        allocator.free(fields.fetchRemove(name).?.key);
                    }
                    
                    try fields.put(name, std.mem.trim(u8, line[separator_index + 1..], " "));
                }
            }
        }

        return Difficulty{
            .allocator = allocator,
            .buffer = owned_buffer,

            .fields = fields,
            .objects = try objects.toOwnedSlice()
        };
    }

    // Deinitialize the difficulty.
    pub fn deinit(self: *Difficulty) void {
        var field_iterator = self.fields.iterator();

        while (field_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.fields.deinit();
        self.allocator.free(self.buffer);
        self.allocator.free(self.objects);
    }

    // Get a field.
    pub fn getField(self: *Difficulty, name: []const u8, default: []const u8) []const u8 {
        return self.fields.get(name) orelse default;
    }

    // Parse a field.
    pub fn parseField(self: *Difficulty, comptime T: type, name: []const u8, default: T) T {
        if (self.fields.get(name)) |value| {
            return switch (@typeInfo(T)) {
                .bool => std.mem.eql(u8, value, "true"),
                .int => std.fmt.parseInt(T, value, 10) catch default,
                .float => std.fmt.parseFloat(T, value, 10) catch default,

                else => @compileError("Unsupported type: " ++ @typeName(T))
            };
        } else {
            return default;
        }
    }

    // Parse a field with a range.
    pub fn parseOptionRange(self: *Difficulty, comptime T: type, name: []const u8, min: ?T, max: ?T, default: T) T {
        if (self.fields.get(name)) |value| {
            const parsed_value = switch (@typeInfo(T)) {
                .int => std.fmt.parseInt(T, value, 10) catch default,
                .float => std.fmt.parseFloat(T, value, 10) catch default,

                else => @compileError("Unsupported type: " ++ @typeName(T))
            };

            if (min != null and parsed_value < min.?)
                return min.?;
            if (max != null and parsed_value > max.?)
                return max.?;

            return parsed_value;
        } else {
            return default;
        }
    }
};
