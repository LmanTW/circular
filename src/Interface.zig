const std = @import("std");

const Interface = @This();

allocator: std.mem.Allocator,
stdout: std.fs.File.Writer,

args: std.ArrayList([]const u8),
opts: std.BufMap,

// Initialize an interface,
pub fn init(allocator: std.mem.Allocator) !Interface {
    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    // Skip the executable itself.
    _ = arg_iterator.skip();

    var args = std.ArrayList([]const u8).init(allocator);
    var opts = std.BufMap.init(allocator);
    errdefer args.deinit();
    errdefer opts.deinit();

    while (arg_iterator.next()) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |separator_index| {
            try opts.put(arg[0..separator_index], arg[separator_index + 1..]);
        } else { 
            try args.append(try allocator.dupe(u8, arg));
        }
    }

    return Interface{
        .allocator = allocator,
        .stdout = std.io.getStdOut().writer(),

        .args = args,
        .opts = opts
    };
}

// Deinitialize the interface,
pub fn deinit(self: *Interface) void {
    for (self.args.items) |arg| {
        self.allocator.free(arg);
    }
 
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
    return self.opts.get(name) orelse default;
}

// Parse an option.
pub fn parseOption(self: *Interface, comptime T: type, name: []const u8, default: T) T {
    if (self.opts.get(name)) |value| {
        if (!std.mem.eql(u8, value, "default")) {
            return switch (@typeInfo(T)) {
                .bool => std.mem.eql(u8, value, "true"),
                .int => std.fmt.parseInt(T, value, 10) catch default,
                .float => std.fmt.parseFloat(T, value, 10) catch default,

                else => @compileError("Unsupported type: " ++ @typeName(T))
            };
        } 
    }
    
    return default;
}

// Parse an option with a range.
pub fn parseOptionRange(self: *Interface, comptime T: type, name: []const u8, min: ?T, max: ?T, default: T) T {
    if (self.opts.get(name)) |value| {
        if (!std.mem.eql(u8, value, "default")) {
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
        } 
    }
    
    return default;
}

// Write something to stdout.
pub fn write(self: *Interface, buffer: []const u8) void {
    _ = self.stdout.write(buffer) catch {};
}

// Print something to stdout.
pub fn print(self: *Interface, comptime fmt: []const u8, args: anytype) void {
    self.stdout.print(fmt, args) catch {};
}

// Log something.
pub fn log(self: *Interface, kind: Kind, comptime fmt: []const u8, args: anytype) void {
    const format = self.getOption("log.format", "verbose");

    if (std.mem.eql(u8, format, "verbose")) {
        const content = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        defer self.allocator.free(content);

        switch (kind) {
            .Info =>     self.print(" \x1B[35m[ Info     ]: {s}\x1B[0m\n", .{content}),
            .Warning =>  self.print(" \x1B[33m[ Warning  ]: {s}\x1B[0m\n", .{content}),
            .Error =>    self.print(" \x1B[31m[ Error    ]: {s}\x1B[0m\n", .{content}),

            .Running =>  self.print(" \x1B[39m[ Running  ]: {s}\x1B[0m\n", .{content}),
            .Progress => self.print(" \x1B[39m[ Progress ]: {s}\x1B[0m\n", .{content}),
            .Complete => self.print(" \x1B[32m[ Complete ]: {s}\x1B[0m\n", .{content}),

            .Debug => {
                if (std.mem.eql(u8, self.getOption("log.level", "info"), "debug")) {
                    self.print(" \x1B[36m[ Debug    ]: {s}\x1B[0m\n", .{content});
                }
            }
        }
    } else if (std.mem.eql(u8, format, "json")) {
        if (kind != .Debug or std.mem.eql(u8, self.getOption("log.level", "info"), "debug")) {
            const content = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
            defer self.allocator.free(content);

            const json = std.json.stringifyAlloc(self.allocator, .{ .kind = @tagName(kind), .content = content, .args = args }, .{}) catch return;
            defer self.allocator.free(json);

            self.print("{s}\n", .{json});
        } 
    }
}

// Log a blank line.
pub fn blank(self: *Interface) void {
    const format = self.getOption("log.format", "verbose");

    if (std.mem.eql(u8, format, "verbose")) {
        self.write("\n");
    }
}

// The kind of the log.
pub const Kind = enum(u4) {
    Running,
    Progress,
    Complete,

    Info,
    Warning,
    Error,

    Debug,
};
