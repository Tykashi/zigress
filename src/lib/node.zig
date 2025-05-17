const std = @import("std");
const Handler = @import("./handler.zig").Handler;
const HandlerMap = @import("./handler.zig").HandlerMap;
pub const NodeMap = std.StringHashMap(Node);
pub const Node = struct {
    terminal: bool = false,
    children: NodeMap,
    handlers: HandlerMap,

    pub fn init(allocator: std.mem.Allocator) Node {
        return .{ .children = NodeMap.init(allocator), .handlers = HandlerMap.init(allocator) };
    }

    pub fn deinit(self: *Node) void {
        var iter = self.children.valueIterator();
        while (iter.next()) |node| node.deinit();
        self.children.deinit();
    }
};
