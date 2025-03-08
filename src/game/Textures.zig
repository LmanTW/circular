const Surface = @import("../graphic/Surface.zig");
const Texture = @import("../graphic/Texture.zig");

const std = @import("std");

const Textures = @This();

allocator: std.mem.Allocator,
textures: std.StringHashMap(Texture),
backend: Surface.Backend,

// Initialize a texture pool.
pub fn init(backend: Surface.Backend, allocator: std.mem.Allocator) Textures {
    return Textures{
        .allocator = allocator,
        .textures = std.StringHashMap(Texture).init(allocator),
        .backend = backend
    };
}

// Deinitialize the texture pool.
pub fn deinit(self: *Textures) void {
    self.clear();
    self.textures.deinit();
}

// Clear the texture pool.
pub fn clear(self: *Textures) void {
    var texture_iterator = self.textures.iterator();

    while (texture_iterator.next()) |entry| {
         self.allocator.free(entry.key_ptr.*);
         entry.value_ptr.*.deinit();
    }
}

// Load a texture.
// > [name, data, default] is no longer required after loaded.
pub fn loadTexture(self: *Textures, name: []const u8, data: ?[]u8, default: []const u8, style: Texture.Style) !void {
    if (self.textures.contains(name)) {
        const entry = self.textures.fetchRemove(name).?;

        self.allocator.free(entry.key);
        @constCast(&entry.value).deinit();
    }

    const name_buffer = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_buffer);

    try self.textures.put(name_buffer, try Texture.init(self.backend, data orelse @constCast(default), style, self.allocator));
}

// Get a texture.
pub fn getTexture(self: *Textures, name: []const u8) !Texture {
    return self.textures.get(name) orelse error.TextureNotFound;
}
