const std = @import("std");
const MPMCQueue = @import("zdsa").MPMCQueue;
const ServerConfig = @import("server_config.zig").ServerConfig;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Router = @import("router.zig").Router;
const Handler = @import("handler.zig").Handler;

pub const Server = struct {
    allocator: std.mem.Allocator,

    config: ServerConfig,
    sock_fd: std.posix.socket_t,
    addr: std.net.Address,
    queue: *MPMCQueue(std.posix.socket_t),
    workers: []std.Thread,
    router: Router,

    pub fn init(
        allocator: std.mem.Allocator,
        config: ServerConfig,
    ) !*Server {
        const self = try allocator.create(Server);

        const address = try std.net.Address.parseIp(config.listen_address, config.listen_port);

        const sock_fd = try std.posix.socket(address.in.sa.family, config.socket_flags, std.posix.IPPROTO.TCP);
        try std.posix.setsockopt(sock_fd, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1)));
        try std.posix.setsockopt(sock_fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        const queue = try MPMCQueue(std.posix.socket_t).init(allocator, config.queue_capacity);
        const threads = try allocator.alloc(std.Thread, config.worker_count);

        for (threads) |*t| {
            t.* = try std.Thread.spawn(.{}, Server.workerMain, .{ queue, self });
        }

        const router = try Router.init(allocator);

        self.* = Server{
            .allocator = allocator,
            .sock_fd = sock_fd,
            .addr = address,
            .queue = queue,
            .workers = threads,
            .config = config,
            .router = router,
        };

        return self;
    }

    fn bind(self: *Server) !void {
        try std.posix.bind(self.sock_fd, &self.addr.any, self.addr.in.getOsSockLen());
    }

    pub fn listen(self: *Server) !void {
        try self.bind();
        _ = try std.posix.listen(self.sock_fd, 1024);

        while (true) {
            const client_sock = try std.posix.accept(self.sock_fd, null, null, 0);
            self.queue.enqueue(client_sock);
        }
    }

    fn workerMain(queue: *MPMCQueue(std.posix.socket_t), server: *Server) !void {
        while (true) {
            const sock = queue.dequeue();
            defer std.posix.close(sock);

            var raw_msg: [32768]u8 = undefined;
            const read_len = std.posix.read(sock, &raw_msg) catch |err| {
                std.log.err("Failed to read: {}", .{err});
                continue;
            };

            if (read_len == 0) continue;

            const request_data = raw_msg[0..read_len];

            var arena = std.heap.ArenaAllocator.init(server.allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            var request = Request.parse(request_data, allocator) catch |err| {
                std.log.err("Failed to parse request: {}", .{err});
                continue;
            };

            var response = try allocator.create(Response);
            response.* = Response.init(allocator, sock);
            defer response.deinit();

            const route = server.router.search(request.method, request.path);
            if (route) |handler| {
                try handler(&request, response);
            } else {
                response.setStatus(404);
                try response.write("404 Not Found");
            }

            if (!response.sent) {
                try response.send();
            }
        }
    }
    pub fn GET(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("GET", path, handler);
    }
    pub fn PUT(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("PUT", path, handler);
    }

    pub fn POST(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("POST", path, handler);
    }

    pub fn PATCH(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("PATCH", path, handler);
    }

    pub fn DELETE(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("DELETE", path, handler);
    }

    pub fn OPTIONS(self: *Server, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert("OPTIONS", path, handler);
    }

    pub fn CUSTOM(self: *Server, method: []const u8, path: []const u8, handler: Handler) anyerror!void {
        try self.router.insert(method, path, handler);
    }

    pub fn deinit(self: *Server) void {
        self.queue.deinit(self.allocator);
        self.allocator.free(self.workers);
        self.allocator.destroy(self);
    }
};
