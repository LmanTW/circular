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
        entry.value_ptr.*.deinit();
    }
}

// Load a texture.
pub fn load(self: *Textures, name: []const u8, data: []u8) !void {
    if (self.textures.contains(name)) {
        @constCast(&self.textures.fetchRemove(name).?.value).deinit();
    }

    try self.textures.put(name, try Texture.init(self.backend, data, self.allocator));
}

// Get a texture.
pub fn get(self: *Textures, name: []const u8) ?Texture {
    return self.textures.get(name);
}
