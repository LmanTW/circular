const std = @import("std");

const Skin = @This();

allocator: std.mem.Allocator,
fields: std.StringHashMap([]const u8),
resources: std.StringHashMap([]u8),

// Initialize a skin from a file.
// > [file] is no longer required after initializaion.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Skin {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator);
}

// Initialize a skin from the memory.
// > [buffer] is no longer required after initializaion.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Skin {
    var buffer_stream = std.io.fixedBufferStream(buffer);
    var seekable_stream = buffer_stream.seekableStream();
    var reader = seekable_stream.context.reader();

    var fields = std.StringHashMap([]const u8).init(allocator);
    var resources = std.StringHashMap([]u8).init(allocator);

    errdefer {
        var field_iterator = fields.iterator();
        var resource_iterator = resources.iterator();

        while (field_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }

        while (resource_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }

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

        try resources.put(filename, content);
    }

    if (resources.get("skin.ini")) |content| {
        var line_iterator = std.mem.tokenizeAny(u8, content, "\r\n");
        var current_section = @as(?[]const u8, null);
        var current_keys = @as(?u8, null);

        while (line_iterator.next()) |line| {
            if (line.len > 0 and (line[0] == '[' and line[line.len - 1] == ']')) {
                current_section = line[1..line.len - 1];
                current_keys = null;
            } else if (current_section != null) {
                if (std.mem.indexOfScalar(u8, line, ':')) |separator_index| {
                    const key = std.mem.trim(u8, line[0..separator_index], " ");
                    const value = std.mem.trim(u8, line[separator_index + 1..], " ");

                    if (std.mem.eql(u8, current_section.?, "Mania") and current_keys == null) {
                        if (std.mem.eql(u8, key, "Keys")) {
                            current_keys = try std.fmt.parseInt(u8, value, 10);
                        }
                    } else {
                        var name = @as([]const u8, undefined);
                        
                        if (std.mem.eql(u8, current_section.?, "Mania")) {
                            name = try std.fmt.allocPrint(allocator, "Mania{}.{s}", .{current_keys.?, key});
                        } else {
                            name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{current_section.?, key});
                        }

                        errdefer allocator.free(name);

                        if (fields.contains(name)) {
                            allocator.free(fields.fetchRemove(name).?.key);
                        }

                        try fields.put(name, value);
                    } 
                }
            }
        }
    }
    
    return Skin{
        .allocator = allocator,
        .fields = fields,
        .resources = resources
    };
}

// Deinitialize the skin.
pub fn deinit(self: *Skin) void {
    var field_iterator = self.fields.iterator();
    var resource_iterator = self.resources.iterator();

    while (field_iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }

    while (resource_iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }

    self.fields.deinit();
    self.resources.deinit();
}

// Get a field.
pub fn getField(self: *Skin, name: []const u8, default: []const u8) []const u8 {
    return self.fields.get(name) orelse default;
}

// Parse a field.
pub fn parseField(self: *Skin, comptime T: type, name: []const u8, default: T) T {
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
pub fn parseOptionRange(self: *Skin, comptime T: type, name: []const u8, min: ?T, max: ?T, default: T) T {
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
