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
    middleware: std.ArrayList(Handler),
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
            .middleware = std.ArrayList(Handler).init(allocator),
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

            var buffer: [32768]u8 = undefined;
            var total_read: usize = 0;

            var arena = std.heap.ArenaAllocator.init(server.allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            var response = allocator.create(Response) catch |err| {
                std.log.err("Failed to create response: {s}", .{@errorName(err)});
                continue;
            };
            response.* = Response.init(allocator, sock);
            defer response.deinit();

            var request: ?Request = null;

            // Read until complete request or fail
            while (true) {
                const n = std.posix.read(sock, buffer[total_read..]) catch |err| {
                    std.log.err("Read error: {s}", .{@errorName(err)});
                    break;
                };
                if (n == 0) break; // client closed
                total_read += n;

                const parse_result = Request.parse(buffer[0..total_read], allocator) catch |err| {
                    std.log.err("Parse error: {s}", .{@errorName(err)});
                    break;
                };

                switch (parse_result) {
                    .NeedMore => |_| {
                        if (total_read >= buffer.len) {
                            std.log.err("Request too large", .{});
                            break;
                        }
                        continue;
                    },
                    .Complete => |req| {
                        request = req;
                        break;
                    },
                }
            }

            if (request == null) continue;
            const req_ptr = &request.?;

            for (server.middleware.items) |mw| {
                if (mw(req_ptr, response)) |err| {
                    std.log.err("Middleware error: {s}", .{@errorName(err)});
                    response.setStatus(500);
                    _ = response.write("Internal Server Error") catch {};
                    break; // stop further processing
                }
            }

            const route = server.router.search(req_ptr.method, req_ptr.path);
            if (route) |handler| {
                if (handler(req_ptr, response)) |err| {
                    std.log.err("Handler error: {s}", .{@errorName(err)});
                    response.setStatus(500);
                    _ = response.write("Internal Server Error") catch {};
                }
            } else {
                response.setStatus(404);
                _ = response.write("404 Not Found") catch {};
            }

            if (!response.sent) {
                _ = response.send() catch |err| {
                    std.log.err("Send error: {s}", .{@errorName(err)});
                };
            }
        }
    }

    pub fn USE(self: *Server, handler: Handler) !void {
        try self.middleware.append(handler);
    }

    fn CORS(self: *Server, path: []const u8, handler: Handler) !void {
        try self.router.insert("OPTIONS", path, handler);
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
        self.middleware.deinit();
    }
};
