const std = @import("std");
const Node = @import("./node.zig").Node;
const NodeMap = @import("./node.zig").NodeMap;
const Handler = @import("./handler.zig").Handler;

pub const Router = @This();
root: Node,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Router {
    std.log.info("Router initialized", .{});
    return .{
        .allocator = allocator,
        .root = Node.init(allocator),
    };
}

pub fn deinit(self: *Router) void {
    std.log.info("Router deinit", .{});
    self.root.deinit();
}

pub fn insert(self: *Router, method: []const u8, path: []const u8, handler: Handler) !void {
    std.log.info("Inserting route: method={s}, path={s}", .{ method, path });

    // Special case for root route `/`
    if (std.mem.eql(u8, path, "/")) {
        self.root.terminal = true;
        const hand = try self.root.handlers.getOrPut(method);
        hand.value_ptr.* = handler;
        std.log.info("✔ Registered root route handler for method={s}", .{method});
        return;
    }

    var node = &self.root;
    var iterator = std.mem.tokenizeAny(u8, path, "/");

    while (true) {
        const segment = iterator.next() orelse break;
        std.log.info("  Processing segment: {s}", .{segment});
        var gop = try node.*.children.getOrPut(segment);
        if (!gop.found_existing) {
            gop.value_ptr.* = Node.init(self.allocator);
            std.log.info("    ↳ Created new node for segment: {s}", .{segment});
        }

        if (iterator.peek() == null) {
            gop.value_ptr.terminal = true;
            const hand = try gop.value_ptr.handlers.getOrPut(method);
            hand.value_ptr.* = handler;
            std.log.info("    ✔ Handler registered for method={s} at path segment={s}", .{ method, segment });
            break;
        }

        node = gop.value_ptr;
    }
}

pub fn search(self: *Router, method: []const u8, path: []const u8) ?Handler {
    std.log.info("Searching for route: method={s}, path={s}", .{ method, path });

    var node = &self.root;

    // Special case for root path `/`
    if (std.mem.eql(u8, path, "/")) {
        if (node.terminal) {
            const maybe = node.handlers.get(method);
            std.log.info("  ✔ Matched root handler for method={s}: found={}", .{ method, maybe != null });
            return maybe;
        } else {
            std.log.warn("  ✘ Root is not terminal", .{});
            return null;
        }
    }

    var iterator = std.mem.tokenizeAny(u8, path, "/");

    while (iterator.next()) |segment| {
        std.log.info("  → Looking for segment: {s}", .{segment});
        const child = node.children.get(segment) orelse {
            std.log.warn("    ✘ No child for segment: {s}", .{segment});
            return null;
        };
        node = child;
    }

    if (node.terminal) {
        const maybe = node.handlers.get(method);
        std.log.info("  ✔ Terminal node reached. Handler found={}", .{maybe != null});
        return maybe;
    } else {
        std.log.warn("  ✘ Node not terminal at end of path", .{});
        return null;
    }
}
