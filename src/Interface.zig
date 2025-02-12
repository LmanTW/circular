const std = @import("std");

const Interface = @This();

allocator: std.mem.Allocator,
stdout: std.fs.File.Writer,

args: std.ArrayList([]const u8),
opts: std.StringArrayHashMap([]const u8),

// Initialize an interface.
pub fn init(allocator: std.mem.Allocator) !Interface {
    var iterator = try std.process.argsWithAllocator(allocator);
    defer iterator.deinit();

    // Skip the executable itself.
    _ = iterator.skip();

    var args = std.ArrayList([]const u8).init(allocator);
    var opts = std.StringArrayHashMap([]const u8).init(allocator);

    while (iterator.next()) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |separator_index| {
            try opts.put(arg[0..separator_index], arg[separator_index + 1..]);
        } else {
            try args.append(arg);
        }
    }

    return Interface{
        .allocator = allocator,
        .stdout = std.io.getStdOut().writer(),

        .args = args,
        .opts = opts
    };
}

// Deinitialize the interface.
pub fn deinit(self: *Interface) void {
    self.args.deinit();
    self.opts.deinit();
}

// Get an argument.
pub fn getArgument(self: *Interface, index: usize) []const u8 {
    return self.args.items[index];
}

// Count the arguments.
pub fn countArguments(self: *Interface) usize {
    return self.args.items.len;
}

// Get an option.
pub fn getOption(self: *Interface, name: []const u8, default: []const u8) []const u8 {
    if (self.opts.get(name)) |value| {
        return value;
    } else {
        return default;
    }
}

// Get an option and parse it.
pub fn parseOption(self: *Interface, comptime T: type, name: []const u8, default: T) T {
    if (self.opts.get(name)) |value| { 
        return switch (T) {
            bool => std.mem.eql(u8, value, "true"),
            u8, u16, u32, u64, usize => std.fmt.parseInt(T, value, 10) catch null,
            f32, f64 => std.fmt.parseFloat(T, value) catch null,

            else => @compileError("Unsupported type")
        } orelse default;
    } else {
        return default;
    }    
}

// Count the options.
pub fn countOptions(self: *Interface) usize {
    return self.opts.count();
}

// Log something.
pub fn log(self: *Interface, label: Label, comptime fmt: []const u8, args: anytype) !void {
    const format = self.getOption("log", "verbose");

    if (std.mem.eql(u8, format, "verbose")) {
        const content = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(content);

        switch (label) {
            .Info =>     try self.stdout.print(" \x1B[90m[ Info     ]: {s}\x1B[0m\n", .{content}),
            .Warning =>  try self.stdout.print(" \x1B[33m[ Warning  ]: {s}\x1B[0m\n", .{content}),
            .Error =>    try self.stdout.print(" \x1B[31m[ Error    ]: {s}\x1B[0m\n", .{content}),

            .Running =>  try self.stdout.print(" \x1B[39m[ Running  ]: {s}\x1B[0m\n", .{content}),
            .Progress => try self.stdout.print(" \x1B[39m[ Progress ]: {s}\x1B[0m\n", .{content}),
            .Complete => try self.stdout.print(" \x1B[32m[ Complete ]: {s}\x1B[0m\n", .{content})
        }
    } else if (std.mem.eql(u8, format, "json")) {
        const content = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(content);

        const json = try std.json.stringifyAlloc(self.allocator, .{ .label = @tagName(label), .content = content, .args = args }, .{});
        defer self.allocator.free(json);

        try self.stdout.print("{s}\n", .{json});
    }
}

// Log a blank line.
pub fn blank(self: *Interface) !void {
    const format = self.getOption("log", "verbose");

    // Only log the blank line if the log format is "verbose".
    if (std.mem.eql(u8, format, "verbose")) {
        _ = try self.stdout.write("\n");
    }
}

// The label of the log.
pub const Label = enum {
    Running,
    Progress,
    Complete,

    Info,
    Warning,
    Error   
};
