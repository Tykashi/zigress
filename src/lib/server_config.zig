const std = @import("std");

pub const ServerConfig = struct { listen_address: []const u8, listen_port: u16, req_buffer_size: usize = 32000, socket_flags: u32 = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, worker_count: usize = 32, queue_capacity: usize = 1024 };
