const Surface = @import("../graphic/Surface.zig");
const Texture = @import("../graphic/Texture.zig");

const std = @import("std");

const Appearance = @This();

allocator: std.mem.Allocator,
backend: Surface.Backend,

fields: std.StringHashMap([]const u8),
textures: std.StringHashMap(Texture),

// Initialize an appearance.
pub fn init(backend: Surface.Backend, allocator: std.mem.Allocator) Appearance {
    return Appearance{
        .allocator = allocator,
        .backend = backend,

        .fields = std.StringHashMap([]const u8).init(allocator),
        .textures = std.StringHashMap(Texture).init(allocator)
    };
}

// Deinitialize the appearance.
pub fn deinit(self: *Appearance) void {
    self.clear();

    self.fields.deinit();
    self.textures.deinit();
}

// Clear the appearance.
pub fn clear(self: *Appearance) void {
    var field_iterator = self.fields.iterator();
    var texture_iterator = self.textures.iterator();

    while (field_iterator.next()) |entry| {
         self.allocator.free(entry.key_ptr.*);
         self.allocator.free(entry.value_ptr.*);
    }

    while (texture_iterator.next()) |entry| {
         self.allocator.free(entry.key_ptr.*);
         entry.value_ptr.*.deinit();
    }
}

// Set a field.
// > [name, value] is no longer required after the field is set.
pub fn setField(self: *Appearance, name: []const u8, value: []const u8) !void {
    if (self.textures.contains(name)) {
        const entry = self.fields.fetchRemove(name).?;

        self.allocator.free(entry.key);
        self.allocator.free(entry.value);
    }

    const name_buffer = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_buffer);

    const value_buffer = try self.allocator.dupe(u8, value);
    errdefer self.allocator.free(value_buffer);

    try self.fields.put(name_buffer, value_buffer);
}

// Get a field.
pub fn getField(self: *Appearance, name: []const u8, default: []const u8) []const u8 {
    return self.fields.get(name) orelse default;
}

// Parse a field.
pub fn parseField(self: *Appearance, comptime T: type, name: []const u8, default: T) T {
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

// Load a texture.
// > [name, data, default] is no longer required after loaded.
pub fn loadTexture(self: *Appearance, name: []const u8, data: ?[]u8, default: []const u8) !void {
    if (self.textures.contains(name)) {
        const entry = self.textures.fetchRemove(name).?;

        self.allocator.free(entry.key);
        @constCast(&entry.value).deinit();
    }

    const name_buffer = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_buffer);

    try self.textures.put(name_buffer, try Texture.init(self.backend, data orelse @constCast(default), self.allocator));
}

// Get a texture.
pub fn getTexture(self: *Appearance, name: []const u8) !Texture {
    return self.textures.get(name) orelse error.TextureNotFound;
}
