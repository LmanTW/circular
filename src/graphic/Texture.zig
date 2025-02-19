const std = @import("std");

const Texture = @This();

allocator: std.mem.Allocator,
unmanaged: *anyopaque,

width: u16,
height: u16,

backend: Backend,
vtable: *const VTable,

// The vtable.
pub const VTable = struct {
    deinit: *const fn(ptr: *anyopaque) void
};

// Deinitialize the texture.
pub fn deinit(self: *Texture) void {
    self.vtable.deinit(self.unmanaged);
}

// The backend.
pub const Backend = enum(u4) {
    Basic,
    OpenGL
};
