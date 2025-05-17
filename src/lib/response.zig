const std = @import("std");

pub const Response = struct {
    version: []const u8 = "HTTP/1.1",
    status_code: u16 = 200,
    sent: bool = false,

    allocator: std.mem.Allocator,
    client_fd: std.posix.socket_t,

    headers: std.ArrayListAligned(Header, null),
    body_chunks: std.ArrayListAligned([]const u8, null),

    pub const Header = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, client_fd: std.posix.socket_t) Response {
        return Response{
            .allocator = allocator,
            .client_fd = client_fd,
            .headers = std.ArrayListAligned(Header, null).init(allocator),
            .body_chunks = std.ArrayListAligned([]const u8, null).init(allocator),
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        self.body_chunks.deinit();
    }

    pub fn setStatus(self: *Response, code: u16) void {
        self.status_code = code;
    }

    pub fn addHeader(self: *Response, key: []const u8, value: []const u8) !void {
        try self.headers.append(.{ .key = key, .value = value });
    }

    pub fn write(self: *Response, chunk: []const u8) !void {
        try self.body_chunks.append(chunk);
    }

    pub fn send(self: *Response) !void {
        if (self.sent) return;
        self.sent = true;

        const response_bytes = try self.buildResponse();
        _ = try std.posix.write(self.client_fd, response_bytes);
    }

    fn buildResponse(self: *Response) ![]const u8 {
        const body = try std.mem.join(self.allocator, "", self.body_chunks.items);

        if (!self.hasHeader("Content-Length")) {
            const len_str = try std.fmt.allocPrint(self.allocator, "{}", .{body.len});
            try self.addHeader("Content-Length", len_str);
        }

        if (!self.hasHeader("Content-Type")) {
            try self.addHeader("Content-Type", "text/plain");
        }

        var header_lines = std.ArrayList([]const u8).init(self.allocator);
        defer header_lines.deinit();

        for (self.headers.items) |h| {
            try header_lines.append(try std.fmt.allocPrint(self.allocator, "{s}: {s}\r\n", .{ h.key, h.value }));
        }

        const headers_joined = try std.mem.join(self.allocator, "", header_lines.items);
        const status_text = statusMessage(self.status_code);

        const head = try std.fmt.allocPrint(
            self.allocator,
            "{s} {d} {s}\r\n{s}\r\n",
            .{ self.version, self.status_code, status_text, headers_joined },
        );

        return try std.mem.concat(self.allocator, u8, &.{ head, body });
    }

    fn hasHeader(self: *Response, key: []const u8) bool {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.key, key)) return true;
        }
        return false;
    }

    fn statusMessage(code: u16) []const u8 {
        return switch (code) {
            200 => "OK",
            201 => "Created",
            202 => "Accepted",
            204 => "No Content",
            301 => "Moved Permanently",
            302 => "Found",
            304 => "Not Modified",
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            408 => "Request Timeout",
            409 => "Conflict",
            410 => "Gone",
            415 => "Unsupported Media Type",
            418 => "I'm a teapot",
            429 => "Too Many Requests",
            500 => "Internal Server Error",
            501 => "Not Implemented",
            502 => "Bad Gateway",
            503 => "Service Unavailable",
            504 => "Gateway Timeout",
            else => "Unknown Status",
        };
    }
};

