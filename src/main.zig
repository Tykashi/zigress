const std = @import("std");

const Server = @import("root.zig").Server;

const routes = @import("lib/routes/routes.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const server = try Server.init(alloc, .{
        .listen_address = "127.0.0.1",
        .listen_port = 8080,
        .req_buffer_size = 32000,
    });

    try server.GET("/health", &routes.GetHealth);
    try server.GET("/health/check", &routes.Check);
    try server.listen();
}
