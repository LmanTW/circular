const std = @import("std");

const Worker = @This();

status: std.atomic.Value(Status),
ctx: ?*anyopaque,
function: ?*const fn(ptr: *anyopaque) void,

// The status.
pub const Status = enum(u8) {
    Idle,
    Working,
    Waiting,
    Killing,
    Unknown
};

// Initialize a worker.
pub fn init() Worker {
    return Worker{
        .status = std.atomic.Value(Status).init(.Unknown),
        .ctx = null,
        .function = null,
    };
}

// Bind the worker to a thread.
pub fn bind(self: *Worker) void {
    self.status.store(.Idle, .release);

    while (true) {
        var status = self.status.load(.acquire);

        while (status == .Idle or status == .Waiting) {
            std.Thread.sleep(std.time.ns_per_ms);

            status = self.status.load(.acquire);
        }

        if (status == .Killing) {
            self.status.store(.Unknown, .release);

            return;
        }

        const ctx = self.ctx orelse unreachable;
        const function = self.function orelse unreachable;

        function(ctx);

        self.status.store(.Waiting, .release);
    }
}

// Unbind the worker.
pub fn unbind(self: *Worker) !void {
    switch (self.status.load(.acquire)) {
        .Killing => return error.AlreadyKilling,
        .Unknown => return error.Unavailable,

        else => {
            self.status.store(.Killing, .release);

            while (self.status.load(.acquire) == .Killing) {
                std.Thread.sleep(std.time.ns_per_ms);
            }
        }
    }
}

// Assign a task to the worker.
pub fn assign(self: *Worker, ctx: *anyopaque, function: *const fn(ptr: *anyopaque) void) !void {
    switch (self.status.load(.acquire)) {
        .Idle => {
            self.ctx = ctx;
            self.function = function;
            self.status.store(.Working, .release);
        },

        .Working => return error.AlreadyWorking,
        .Waiting => return error.AlreadyWaiting,
        .Killing => return error.AlreadyKilling,
        .Unknown => return error.Unavailable
    }
}

// Wait until the worker finished working.
pub fn wait(self: *Worker) !void {
    switch (self.status.load(.acquire)) {
        .Working, .Waiting => {
            while (self.status.load(.acquire) != .Waiting) {
                std.Thread.sleep(std.time.ns_per_ms);
            }

            self.status.store(.Idle, .release);
        },

        else => return error.NotWorking
    }
}

// Worker group.
pub const Group = struct {
    allocator: std.mem.Allocator,
    workers: []Worker,
    tasks: ?[]Group.Task,

    // Initialize the worker group.
    pub fn init(size: u8, allocator: std.mem.Allocator) !Group {
        const workers = try allocator.alloc(Worker, size);

        for (0..workers.len) |index| {
            workers[index] = Worker.init();
            
            _ = try std.Thread.spawn(.{}, bind, .{@constCast(&workers[index])});
        }

        return Group{
            .allocator = allocator,

            .workers = workers,
            .tasks = null
        };
    }

    // Deinitialize the worker group.
    pub fn deinit(self: *Group) void {
        for (0..self.workers.len) |index| {
            @constCast(&self.workers[index]).unbind() catch {};
        }

        self.allocator.free(self.workers);
    }

    // Assign tasks to the workers.
    pub fn assign(self: *Group, ctx: *anyopaque, function: *const fn(ctx: *anyopaque, range: [2]u64) void, range: [2]u64) !void {
        if (self.tasks != null) {
            return error.AlreadyWorking;
        }

        const tasks = try self.allocator.alloc(Group.Task, self.workers.len);
        errdefer self.allocator.free(tasks);

        const chunk_size = @divFloor(range[1] - range[0], self.workers.len);

        for (0..self.workers.len) |index| {
            tasks[index] = Task{
                .ctx = ctx,
                .function = function,

                .start = range[0] + (index * chunk_size),
                .end = @min(range[0] + (index * chunk_size) + chunk_size, range[1])
            };

            try @constCast(&self.workers[index]).assign(&tasks[index], Group.Task.execute);
        }

        self.tasks = tasks;
    }

    // Wait the workers to finish working.
    pub fn wait(self: *Group) !void {
        if (self.tasks == null) {
            return error.NotWorking;
        }

        for (0..self.workers.len) |index| {
            try @constCast(&self.workers[index]).wait();
        }

        self.allocator.free(self.tasks.?);
        self.tasks = null;
    }

    // The task.
    pub const Task = struct {
        ctx: *anyopaque,
        function: *const fn(ptr: *anyopaque, range: [2]u64) void,

        start: usize,
        end: usize,

        // Execute the task.
        pub fn execute(ptr: *anyopaque) void {
            const self = @as(*Task, @ptrCast(@alignCast(ptr))); 

            self.function(self.ctx, .{self.start, self.end});
        }
    };
};
