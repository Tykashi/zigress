const std = @import("std");
const Request = @import("./request.zig").Request;
const Response = @import("./response.zig").Response;
pub const Handler = *const fn (request: *Request, response: *Response) anyerror!void;
pub const HandlerMap = std.StringHashMap(Handler);

pub const ContextHandler = struct {
    context: *anyopaque,
    func: *const fn (ctx: *anyopaque, req: *Request, res: *Response) anyerror!void,
};
