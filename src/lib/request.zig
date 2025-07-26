const std = @import("std");

pub const ParseResult = union(enum) {
    Complete: Request,
    NeedMore: usize, // how many more bytes needed
};

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    version: []const u8,
    headers: []Header,
    body: []const u8,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn getHeader(headers: []Header, key: []const u8) ?[]const u8 {
        for (headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, key)) return h.value;
        }
        return null;
    }

    pub fn parse(buf: []const u8, arena: std.mem.Allocator) !ParseResult {
        const header_end = std.mem.indexOf(u8, buf, "\r\n\r\n") orelse return error.MissingHeaderTerminator;
        const header_bytes = buf[0..header_end];
        const body_start = header_end + 4;

        var lines = std.mem.splitScalar(u8, header_bytes, '\n');

        const request_line = lines.next() orelse return error.InvalidRequest;
        const trimmed = std.mem.trimRight(u8, request_line, "\r");

        var parts = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const method = parts.next() orelse return error.InvalidRequest;
        const path = parts.next() orelse return error.InvalidRequest;
        const version = parts.next() orelse return error.InvalidRequest;

        var headers = std.ArrayList(Request.Header).init(arena);
        while (lines.next()) |line| {
            const clean_line = std.mem.trimRight(u8, line, "\r");
            if (clean_line.len == 0) break;

            const colon_index = std.mem.indexOfScalar(u8, clean_line, ':') orelse return error.InvalidHeader;
            const name = std.mem.trim(u8, clean_line[0..colon_index], " ");
            const value = std.mem.trim(u8, clean_line[colon_index + 1 ..], " ");

            try headers.append(.{ .name = name, .value = value });
        }

        const body_len = if (Request.getHeader(headers.items, "Content-Length")) |len_str| blk: {
            break :blk try std.fmt.parseInt(usize, len_str, 10);
        } else 0;

        const available = buf.len - body_start;
        if (available < body_len) {
            return ParseResult{ .NeedMore = (body_len - available) };
        }
        const body = buf[body_start .. body_start + body_len];
        return ParseResult{ .Complete = Request{
            .method = method,
            .path = path,
            .version = version,
            .headers = try headers.toOwnedSlice(),
            .body = body,
        } };
    }
};
