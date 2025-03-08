const std = @import("std");

const Surface = @import("../graphic/Surface.zig");
const Playfield = @import("./Playfield.zig");
const Textures = @import("./Textures.zig");

const Renderer = @This();

allocator: std.mem.Allocator,
surface: Surface,
textures: Textures,

// Initialize a renderer.
pub fn init(backend: Surface.Backend, width: u16, height: u16, threads: u8, allocator: std.mem.Allocator) !Renderer {
    return Renderer{
        .allocator = allocator,
        .surface = try Surface.init(backend, width, height, threads, allocator),
        .textures = Textures.init(backend, allocator)
    };
}

// Deinitialize the renderer.
pub fn deinit(self: *Renderer) void {
    self.surface.deinit();
    self.textures.deinit();
}
