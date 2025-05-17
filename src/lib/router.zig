const std = @import("std");
const Node = @import("./node.zig").Node;
const NodeMap = @import("./node.zig").NodeMap;
const Handler = @import("./handler.zig").Handler;

pub const Router = @This();
root: Node,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Router {
    return .{
        .allocator = allocator,
        .root = Node.init(allocator),
    };
}

pub fn deinit(self: *Router) void {
    self.root.deinit();
}

pub fn insert(self: *Router, method: []const u8, path: []const u8, handler: Handler) !void {
    var node = &self.root;

    var iterator = std.mem.tokenizeAny(u8, path, "/");

    while (true) {
        const segment = iterator.next() orelse break;
        var gop = try node.*.children.getOrPut(segment);
        if (!gop.found_existing) {
            gop.value_ptr.* = Node.init(self.allocator);
            if (std.mem.eql(u8, iterator.peek() orelse "", "")) {
                gop.value_ptr.terminal = true;
                const hand = try gop.value_ptr.handlers.getOrPut(method);
                hand.value_ptr.* = handler;
                break;
            }
            node = gop.value_ptr;
        } else {
            node = gop.value_ptr;
        }
    }
}

pub fn search(self: *Router, method: []const u8, path: []const u8) ?Handler {
    var node = &self.root;
    var iterator = std.mem.tokenizeAny(u8, path, "/");

    while (iterator.next()) |segment| {
        const child = node.children.get(segment) orelse return null;
        node = &child.*;
    }

    if (node.terminal) {
        return node.handlers.get(method);
    }

    return null;
}
