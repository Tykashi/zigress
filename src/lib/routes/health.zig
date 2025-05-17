const std = @import("std");

const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

pub fn GetHealth(request: *Request, response: *Response) anyerror!void {
    std.log.info("Health Check", .{});
    _ = request;
    _ = response;
}
