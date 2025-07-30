const std = @import("std");
const Handler = @import("./handler.zig").Handler;

pub const Node = struct {
    children: std.StringHashMap(*Node),
    terminal: bool = false,
    handlers: std.StringHashMap(Handler),

    pub fn init(allocator: std.mem.Allocator) Node {
        return .{
            .children = std.StringHashMap(*Node).init(allocator),
            .handlers = std.StringHashMap(Handler).init(allocator),
        };
    }

    pub fn deinit(self: *Node) void {
        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.children.deinit();
        self.handlers.deinit();
    }
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    pub fn init(allocator: std.mem.Allocator) !Router {
        const root = try allocator.create(Node);
        root.* = Node.init(allocator);
        return .{
            .allocator = allocator,
            .root = root,
        };
    }

    pub fn deinit(self: *Router) void {
        self.root.deinit();
        self.allocator.destroy(self.root);
    }

    pub fn insert(self: *Router, method: []const u8, path: []const u8, handler: Handler) !void {
        var node = self.root;
        if (std.mem.eql(u8, path, "/")) {
            node.terminal = true;
            const entry = try node.handlers.getOrPut(method);
            entry.value_ptr.* = handler;
            return;
        }

        var iterator = std.mem.tokenizeAny(u8, path, "/");
        while (iterator.next()) |segment| {
            std.log.info("  → Segment: {s}", .{segment});
            const entry = try node.children.getOrPut(segment);
            if (!entry.found_existing) {
                const new_node = try self.allocator.create(Node);
                new_node.* = Node.init(self.allocator);
                entry.value_ptr.* = new_node;
            }
            node = entry.value_ptr.*;
        }

        node.terminal = true;
        const hand_entry = try node.handlers.getOrPut(method);
        hand_entry.value_ptr.* = handler;
    }

    pub fn search(self: *Router, method: []const u8, path: []const u8) ?Handler {
        var node = self.root;
        if (std.mem.eql(u8, path, "/")) {
            if (node.terminal) {
                const handler = node.handlers.get(method);
                return handler;
            }
            return null;
        }

        var iterator = std.mem.tokenizeAny(u8, path, "/");
        while (iterator.next()) |segment| {
            const child = node.children.get(segment) orelse {
                return null;
            };
            node = child;
        }

        if (node.terminal) {
            const handler = node.handlers.get(method);
            return handler;
        } else {
            return null;
        }
    }
};
