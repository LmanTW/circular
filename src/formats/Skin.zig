const std = @import("std");

const Skin = @This();

allocator: std.mem.Allocator,
resources: std.StringArrayHashMap([]u8),

// Initialize a skin from a file.
pub fn initFromFile(file: std.fs.File, allocator: std.mem.Allocator) !Skin {
    const buffer = try allocator.alloc(u8, try file.getEndPos());
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return try initFromMemory(buffer, allocator);
}

// Initialize a skin from the memory.
pub fn initFromMemory(buffer: []u8, allocator: std.mem.Allocator) !Skin {
    var buffer_stream = std.io.fixedBufferStream(buffer);
    var seekable_stream = buffer_stream.seekableStream();

    var iterator = try std.zip.Iterator(@TypeOf(seekable_stream)).init(seekable_stream);  
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

        try resources.put(filename, file_data);
    }

    return Skin{
        .allocator = allocator,
        .resources = resources
    };
}

// Deinit the skin.
pub fn deinit(self: *Skin) void {
    var iterator = self.resources.iterator();

    while (iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }

    self.resources.deinit();
}
