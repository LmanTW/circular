const Surface = @import("../graphic/Surface.zig");
const Texture = @import("../graphic/Texture.zig");
const Skin = @import("./formats/Skin.zig");

const std = @import("std");

const Textures = @This();

allocator: std.mem.Allocator,
backend: Surface.Backend,

textures: std.StringHashMap(Texture),
animations: std.StringHashMap(u8),

// Initialize a texture pool.
pub fn init(backend: Surface.Backend, allocator: std.mem.Allocator) Textures {
    return Textures{
        .allocator = allocator,
        .backend = backend,

        .textures = std.StringHashMap(Texture).init(allocator),
        .animations = std.StringHashMap(u8).init(allocator)
    };
}

// Deinitialize the texture pool.
pub fn deinit(self: *Textures) void {
    self.clear();

    self.textures.deinit();
    self.animations.deinit();
}

// Clear the texture pool.
pub fn clear(self: *Textures) void {
    var texture_iterator = self.textures.iterator();
    var animation_iterator = self.animations.iterator();

    while (texture_iterator.next()) |entry| {
         self.allocator.free(entry.key_ptr.*);
         entry.value_ptr.*.deinit();
    }

    while (animation_iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
}

// Load a texture.
// > [name, data, default] are no longer required after loaded.
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

// Load an animated texture.
// > [name, skin, image_name] are no longer required after loaded.
pub fn loadAnimatedTexture(self: *Textures, name: []const u8, skin: *Skin, image_name: []const u8, style: Texture.Style) !void {
    var frames = @as(u8, 0);

    while (true) {
        const image_name_buffer = try std.fmt.allocPrint(self.allocator, "{s}-{}", .{image_name, frames});
        defer self.allocator.free(image_name_buffer);

        if (skin.getImage(image_name_buffer)) |image| {
            const texture_name_buffer = try std.fmt.allocPrint(self.allocator, "{s}-{}", .{image_name, frames});
            errdefer self.allocator.free(texture_name_buffer);

            if (self.textures.contains(texture_name_buffer)) {
               const entry = self.textures.fetchRemove(texture_name_buffer).?;

                self.allocator.free(entry.key);
                @constCast(&entry.value).deinit();
            }

            try self.textures.put(texture_name_buffer, try Texture.init(self.backend, image, style, self.allocator));
        } else {
            break;
        }

        frames += 1;
    }

    if (self.animations.contains(name)) {
        self.allocator.free(self.textures.fetchRemove(name).?.key);
    }

    const name_buffer = self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_buffer);

    try self.animations.put(name_buffer, frames);
}

// Get a texture.
pub fn getTexture(self: *Textures, name: []const u8) !Texture {
    return self.textures.get(name) orelse error.TextureNotFound;
}

// Get a aniamted texture.
pub fn getAnimatedTexture(self: *Textures, name: []const u8, frame: u8) !void {
    var name_buffer = @as([256]u8, undefined);

    return self.textures.get(std.fmt.bufPrint(&name_buffer, "{s}-{}", .{name, frame})) orelse error.TextureNotFound;
}
