const std = @import("std");
const Sha1 = std.crypto.hash.Sha1;
const base64 = std.base64.standard;

pub fn websocketHandshake(
    allocator: std.mem.Allocator,
    sock: std.posix.socket_t,
    sec_key: []const u8,
) !void {
    const ws_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    const concat = try std.mem.concat(allocator, u8, &.{ sec_key, ws_guid });
    defer allocator.free(concat);

    var sha1 = Sha1.init(.{});
    sha1.update(concat);
    const digest = sha1.finalResult();

    var buffer: [base64.Encoder.calcSize(digest.len)]u8 = undefined;
    const encoded = base64.Encoder.encode(&buffer, &digest);

    const response = try std.fmt.allocPrint(allocator,
        \\HTTP/1.1 101 Switching Protocols
        \\Upgrade: "websocket"
        \\Connection: "Upgrade"
        \\Sec-WebSocket-Accept: "{s}"
        \\
    , .{encoded});

    defer allocator.free(response);
    std.log.info("Response: \n{s}", .{response});
    _ = try std.posix.write(sock, response);
}

pub fn handleWebSocketConnection(sock: std.posix.socket_t) !void {
    var buffer: [1024]u8 = undefined;

    while (true) {
        // Read raw WebSocket frame
        const n = try std.posix.read(sock, &buffer);
        if (n == 0) break;

        // Just log for now
        std.debug.print("Received {d} bytes from WebSocket client\n", .{n});

        // Echo it back (not protocol-compliant yet!)
        _ = try std.posix.write(sock, buffer[0..n]);
    }
}
