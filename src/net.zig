//! TCP transport with NINJAM message framing (docs/PROTOCOL.md §1, §2).
//! Frame = 1 type byte + uint32 LE size (<= 16384) + payload.
//! POSIX builds sit directly on std.posix; Windows sits on winsock2.
//! Zig 0.17's std.os.windows.ws2_32 ships the constants/types but not the
//! function externs (std.c getaddrinfo/pollfd are unportable there), so the
//! winsock entry points are declared locally below.

const std = @import("std");
const builtin = @import("builtin");
const bufmod = @import("buf.zig");
const clock = @import("clock.zig");

const is_windows = builtin.os.tag == .windows;

/// Winsock2 surface used by Conn. SOCKET is UINT_PTR.
const winsock = if (is_windows) struct {
    pub const socket_t = usize;
    pub const invalid_socket: socket_t = ~@as(socket_t, 0);
    const socket_error: c_int = -1;

    const AF_INET: c_int = 2;
    const SOCK_STREAM: c_int = 1;
    const IPPROTO_TCP: c_int = 6;
    const TCP_NODELAY: c_int = 1;

    const WSAEINTR: c_int = 10004;
    const WSAEWOULDBLOCK: c_int = 10035;
    const WSAEINPROGRESS: c_int = 10036;
    const WSAEISCONN: c_int = 10056;

    const POLLIN: i16 = 0x0300; // POLLRDNORM | POLLRDBAND
    const POLLOUT: i16 = 0x0010; // POLLWRNORM

    const FIONBIO: c_int = @bitCast(@as(u32, 0x8004667E)); // _IOW('f', 126, u_long)

    const sockaddr_in = extern struct {
        family: u16 = AF_INET,
        port: u16 = 0, // big-endian
        addr: u32 = 0, // big-endian
        zero: [8]u8 = @splat(0),
    };

    const addrinfo = extern struct {
        flags: c_int = 0,
        family: c_int = 0,
        socktype: c_int = 0,
        protocol: c_int = 0,
        addrlen: usize = 0,
        canonname: ?[*:0]u8 = null,
        addr: ?*anyopaque = null,
        next: ?*addrinfo = null,
    };

    const pollfd = extern struct {
        fd: socket_t,
        events: i16,
        revents: i16,
    };

    extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *anyopaque) callconv(.winapi) c_int;
    extern "ws2_32" fn socket(af: c_int, type: c_int, protocol: c_int) callconv(.winapi) socket_t;
    extern "ws2_32" fn connect(s: socket_t, name: *const anyopaque, namelen: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn send(s: socket_t, buf: [*]const u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn recv(s: socket_t, buf: [*]u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn closesocket(s: socket_t) callconv(.winapi) c_int;
    extern "ws2_32" fn ioctlsocket(s: socket_t, cmd: c_int, argp: *c_ulong) callconv(.winapi) c_int;
    extern "ws2_32" fn setsockopt(s: socket_t, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn WSAPoll(fdArray: [*]pollfd, fdCount: c_ulong, timeout: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn WSAGetLastError() callconv(.winapi) c_int;
    extern "ws2_32" fn getaddrinfo(pNodeName: ?[*:0]const u8, pServiceName: ?[*:0]const u8, pHints: ?*const addrinfo, ppResult: *?*addrinfo) callconv(.winapi) c_int;
    extern "ws2_32" fn freeaddrinfo(pAddrInfo: ?*addrinfo) callconv(.winapi) void;

    var booted = false;

    /// Sessions are single-threaded (session.zig), so a plain flag suffices
    /// for the once-only WSAStartup.
    fn ensureStartup() !void {
        if (booted) return;
        var data: [512]u8 align(16) = undefined; // WSADATA, opaque to us
        if (WSAStartup(0x0202, &data) != 0) return error.SystemResources;
        booted = true;
    }
};

const sock_t = if (is_windows) winsock.socket_t else std.posix.socket_t;
const invalid_socket: sock_t = if (is_windows) winsock.invalid_socket else -1;

pub const max_payload: u32 = 16384;

pub const Message = struct {
    mtype: u8,
    payload: []const u8,
};

pub const Error = error{
    BadFrame,
    EndOfStream,
    ConnectionClosed,
} || std.posix.ReadError || std.posix.PollError || std.posix.UnexpectedError || std.mem.Allocator.Error;

pub const Conn = struct {
    io: std.Io = undefined,
    fd: sock_t = invalid_socket,

    rbuf: [65536]u8 = undefined,
    rhead: usize = 0,
    rtail: usize = 0,

    last_recv_ms: i64 = 0,
    last_send_ms: i64 = 0,

    pub fn connect(io: std.Io, host: []const u8, port: u16) !Conn {
        if (is_windows) try winsock.ensureStartup();

        // fast path: dotted-quad IPv4 literal
        if (std.Io.net.Ip4Address.parse(host, port)) |ip4| {
            const sa = sockaddrIn(ip4);
            return connectSockaddr(io, &sa);
        } else |_| {}

        // hostname: getaddrinfo
        const host_z = std.heap.page_allocator.dupeSentinel(u8, host, 0) catch return error.SystemResources;
        defer std.heap.page_allocator.free(host_z);
        var port_buf: [16]u8 = undefined;
        const port_str = std.mem.printSentinel(&port_buf, "{d}", .{port}, 0) catch return error.UnknownHost;

        if (is_windows) {
            const hints: winsock.addrinfo = .{
                .family = winsock.AF_INET,
                .socktype = winsock.SOCK_STREAM,
                .protocol = winsock.IPPROTO_TCP,
            };
            var res: ?*winsock.addrinfo = null;
            if (winsock.getaddrinfo(host_z.ptr, port_str.ptr, &hints, &res) != 0 or res == null) return error.UnknownHost;
            defer winsock.freeaddrinfo(res);

            var it: ?*winsock.addrinfo = res;
            while (it) |ai| : (it = ai.next) {
                if (ai.addrlen == 0 or ai.addr == null) continue;
                const fd = openStreamSocket() catch continue;
                setNoDelay(fd);
                if (winsock.connect(fd, ai.addr.?, @intCast(ai.addrlen)) != 0) {
                    closeFd(fd);
                    continue;
                }
                setNonblocking(fd);
                return connected(io, fd);
            }
            return error.UnknownHost;
        }

        const hints: std.posix.addrinfo = .{
            .flags = .{},
            .family = std.posix.AF.INET,
            .socktype = std.posix.SOCK.STREAM,
            .protocol = std.posix.IPPROTO.TCP,
            .addrlen = 0,
            .canonname = null,
            .addr = null,
            .next = null,
        };
        var res: ?*std.posix.addrinfo = null;
        const rc = std.posix.system.getaddrinfo(host_z.ptr, port_str.ptr, &hints, &res);
        if (rc != @as(std.posix.system.EAI, @fromBackingInt(@intCast(0))) or res == null) return error.UnknownHost;
        defer if (res) |some| std.posix.system.freeaddrinfo(some);

        var it: ?*std.posix.addrinfo = res;
        while (it) |ai| : (it = ai.next) {
            if (ai.addrlen == 0 or ai.addr == null) continue;
            const fd = openStreamSocket() catch continue;
            setNoDelay(fd);
            switch (std.posix.errno(std.posix.system.connect(fd, @ptrCast(@alignCast(ai.addr.?)), @intCast(ai.addrlen)))) {
                .SUCCESS, .INTR, .INPROGRESS, .ISCONN => {},
                else => {
                    closeFd(fd);
                    continue;
                },
            }
            setNonblocking(fd);
            return connected(io, fd);
        }
        return error.UnknownHost;
    }

    fn openStreamSocket() !sock_t {
        if (is_windows) {
            const s = winsock.socket(winsock.AF_INET, winsock.SOCK_STREAM, winsock.IPPROTO_TCP);
            if (s == winsock.invalid_socket) return error.SocketOpen;
            return s;
        }
        const rc = std.posix.system.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        if (std.posix.errno(rc) != .SUCCESS) return error.SocketOpen;
        return @intCast(rc);
    }

    fn closeFd(fd: sock_t) void {
        if (is_windows) {
            _ = winsock.closesocket(fd);
            return;
        }
        _ = std.posix.errno(std.posix.system.close(fd));
    }

    fn setNonblocking(fd: sock_t) void {
        if (is_windows) {
            var mode: c_ulong = 1;
            _ = winsock.ioctlsocket(fd, winsock.FIONBIO, &mode);
            return;
        }
        const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
        // O_NONBLOCK's bit position is not portable (Linux 0o4000, Darwin
        // 0o4, *BSD others): a hardcoded Linux literal silently leaves the
        // socket blocking on macOS, which makes read() hang the session
        // (#13). Take the bit from the target's std.c.O layout instead.
        const nonblock: c_int = @intCast(@as(u32, @bitCast(std.c.O{ .NONBLOCK = true })));
        _ = std.c.fcntl(fd, std.c.F.SETFL, flags | nonblock);
    }

    fn setNoDelay(fd: sock_t) void {
        // latency-sensitive protocol: TCP_NODELAY
        const one: c_int = 1;
        if (is_windows) {
            _ = winsock.setsockopt(fd, winsock.IPPROTO_TCP, winsock.TCP_NODELAY, &one, @sizeOf(c_int));
            return;
        }
        std.posix.setsockopt(fd, std.posix.IPPROTO.TCP, 1, &std.mem.toBytes(one)) catch {};
    }

    const sockaddr_in_t = if (is_windows) winsock.sockaddr_in else std.posix.sockaddr.in;

    fn sockaddrIn(ip4: std.Io.net.Ip4Address) sockaddr_in_t {
        const In = sockaddr_in_t;
        var sa: In = std.mem.zeroes(In);
        if (@hasField(In, "len")) sa.len = @sizeOf(In);
        sa.family = if (is_windows) winsock.AF_INET else std.posix.AF.INET;
        sa.port = std.mem.nativeToBig(u16, ip4.port);
        // sockaddr stores network-order bytes in memory; bytes are already
        // in network order, so a native-endian reinterpretation is correct.
        sa.addr = @bitCast(ip4.bytes);
        return sa;
    }

    fn connectSockaddr(io: std.Io, sa: *const sockaddr_in_t) !Conn {
        const fd = try openStreamSocket();
        errdefer closeFd(fd);
        setNoDelay(fd);
        // blocking connect (like the reference client's jnetlib), then go async
        if (is_windows) {
            if (winsock.connect(fd, sa, @sizeOf(sockaddr_in_t)) != 0) {
                switch (winsock.WSAGetLastError()) {
                    winsock.WSAEINTR, winsock.WSAEINPROGRESS, winsock.WSAEISCONN, winsock.WSAEWOULDBLOCK => {},
                    else => |e| {
                        std.debug.print("connect wsa errno: {d}\n", .{e});
                        return error.ConnectionRefused;
                    },
                }
            }
        } else {
            switch (std.posix.errno(std.posix.system.connect(fd, @ptrCast(sa), @sizeOf(sockaddr_in_t)))) {
                .SUCCESS, .INTR, .INPROGRESS => {},
                .ISCONN => {},
                else => |e| {
                    std.debug.print("connect errno: {any}\n", .{e});
                    return error.ConnectionRefused;
                },
            }
        }
        setNonblocking(fd);
        return connected(io, fd);
    }

    fn connected(io: std.Io, fd: sock_t) Conn {
        return .{
            .io = io,
            .fd = fd,
            .last_recv_ms = clock.nowMs(io),
            .last_send_ms = clock.nowMs(io),
        };
    }

    pub fn close(self: *Conn) void {
        closeFd(self.fd);
        self.fd = invalid_socket;
    }

    pub fn isConnected(self: *const Conn) bool {
        return self.fd != invalid_socket;
    }

    /// poll(2)/WSAPoll on one socket. Returns revents (0 on timeout).
    fn waitSock(fd: sock_t, for_write: bool, timeout_ms: i32) Error!u32 {
        if (is_windows) {
            var fds = [_]winsock.pollfd{.{
                .fd = fd,
                .events = if (for_write) winsock.POLLOUT else winsock.POLLIN,
                .revents = 0,
            }};
            const rc = winsock.WSAPoll(&fds, 1, timeout_ms);
            if (rc == winsock.socket_error) return error.ConnectionClosed;
            if (rc == 0) return 0;
            return @intCast(@as(u32, @bitCast(@as(i32, fds[0].revents))));
        }
        var fds = [_]std.posix.pollfd{.{
            .fd = fd,
            .events = if (for_write) std.posix.POLL.OUT else std.posix.POLL.IN,
            .revents = 0,
        }};
        const n = try std.posix.poll(&fds, timeout_ms);
        if (n == 0) return 0;
        return @intCast(@as(u32, @bitCast(@as(i32, fds[0].revents))));
    }

    /// recv into `buf`. 0 means orderly close; WouldBlock means no data.
    fn readFd(fd: sock_t, buf: []u8) Error!usize {
        if (is_windows) {
            const rc = winsock.recv(fd, buf.ptr, @intCast(@min(buf.len, std.math.maxInt(c_int))), 0);
            if (rc > 0) return @intCast(rc);
            if (rc == 0) return 0;
            return switch (winsock.WSAGetLastError()) {
                winsock.WSAEWOULDBLOCK => error.WouldBlock,
                winsock.WSAEINTR => error.WouldBlock,
                else => error.ConnectionClosed,
            };
        }
        return std.posix.read(fd, buf);
    }

    /// Wait until a message can be read or timeout_ms elapses. Returns true
    /// if readable.
    pub fn pollReadable(self: *Conn, timeout_ms: i32) !bool {
        if (self.fd == invalid_socket) return error.ConnectionClosed;
        // readMessage consumes from rbuf, not the socket: when two frames
        // arrive in one TCP segment the second stays fully buffered with
        // nothing pending on the fd, so it must count as readable.
        if (self.hasBufferedFrame()) return true;
        return try waitSock(self.fd, false, timeout_ms) != 0;
    }

    /// rbuf holds a complete frame, or a header readMessage will reject as
    /// BadFrame. A partial frame is not reported: callers would enter
    /// readMessage, which blocks in ensureBuffered until the rest arrives,
    /// bypassing their timeout.
    fn hasBufferedFrame(self: *const Conn) bool {
        const live = self.rtail - self.rhead;
        if (live < 5) return false;
        const size = std.mem.readInt(u32, self.rbuf[self.rhead + 1 ..][0..4], .little);
        if (self.rbuf[self.rhead] == 0xFF or size > max_payload) return true;
        return live - 5 >= size;
    }

    fn fillMore(self: *Conn) Error!void {
        if (self.fd == invalid_socket) return error.ConnectionClosed;
        // compact if full
        if (self.rtail == self.rbuf.len) {
            if (self.rhead > 0) {
                const live = self.rtail - self.rhead;
                std.mem.copyForwards(u8, self.rbuf[0..live], self.rbuf[self.rhead..self.rtail]);
                self.rhead = 0;
                self.rtail = live;
            } else {
                return error.BadFrame; // >64KiB buffered and still no full frame
            }
        }
        const n = readFd(self.fd, self.rbuf[self.rtail..]) catch |e| switch (e) {
            error.WouldBlock => return,
            else => return e,
        };
        if (n == 0) return error.EndOfStream;
        self.rtail += n;
        self.last_recv_ms = clock.nowMs(self.io);
    }

    fn ensureBuffered(self: *Conn, n: usize) Error!void {
        while (self.rtail - self.rhead < n) {
            const before = self.rtail - self.rhead;
            try self.fillMore();
            if (self.rtail - self.rhead == before) {
                // #13: a partial inbound frame must not pin the session loop —
                // while blocked here neither the --duration deadline nor the
                // stall watchdog can run, and keepalives stop. Keep the bytes
                // buffered and hand control back; the run loop retries on the
                // next readable pass, and a frame that never completes dies to
                // the last_recv_ms watchdog instead of hanging forever.
                return error.WouldBlock;
            }
        }
    }

    /// Read one framed message. `payload` receives a copy of the payload
    /// bytes; the returned Message points into it.
    pub fn readMessage(self: *Conn, payload: *bufmod.Buf) Error!Message {
        try self.ensureBuffered(5);
        const t = self.rbuf[self.rhead];
        var size_bytes: [4]u8 = undefined;
        @memcpy(&size_bytes, self.rbuf[self.rhead + 1 ..][0..4]);
        const size = std.mem.readInt(u32, &size_bytes, .little);
        if (t == 0xFF or size > max_payload) return error.BadFrame;
        try self.ensureBuffered(5 + @as(usize, size));
        payload.clear();
        try payload.add(self.rbuf[self.rhead + 5 ..][0..size]);
        self.rhead += 5 + @as(usize, size);
        return .{ .mtype = t, .payload = payload.items() };
    }

    fn writeAllRaw(self: *Conn, data: []const u8) Error!void {
        if (self.fd == invalid_socket) return error.ConnectionClosed;
        var off: usize = 0;
        while (off < data.len) {
            if (is_windows) {
                const rc = winsock.send(self.fd, data[off..].ptr, @intCast(@min(data.len - off, std.math.maxInt(c_int))), 0);
                if (rc > 0) {
                    off += @intCast(rc);
                    continue;
                }
                switch (winsock.WSAGetLastError()) {
                    winsock.WSAEWOULDBLOCK => _ = try waitSock(self.fd, true, 1000),
                    winsock.WSAEINTR => {},
                    else => return error.ConnectionClosed,
                }
                continue;
            }
            const rc = std.posix.system.write(self.fd, data[off..].ptr, data[off..].len);
            switch (std.posix.errno(rc)) {
                .SUCCESS => off += @intCast(rc),
                .AGAIN => _ = try waitSock(self.fd, true, 1000),
                .INTR => {},
                else => return error.ConnectionClosed,
            }
        }
        self.last_send_ms = clock.nowMs(self.io);
    }

    pub fn sendMessage(self: *Conn, mtype: u8, payload: []const u8) Error!void {
        if (payload.len > max_payload) return error.BadFrame;
        var hdr: [5]u8 = undefined;
        hdr[0] = mtype;
        std.mem.writeInt(u32, hdr[1..5], @intCast(payload.len), .little);
        try self.writeAllRaw(&hdr);
        if (payload.len > 0) try self.writeAllRaw(payload);
    }
};

test "framing constants" {
    try std.testing.expectEqual(@as(u32, 16384), max_payload);
}

test "pollReadable reports complete frames buffered in rbuf" {
    if (is_windows) return error.SkipZigTest;
    var sv: [2]std.c.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &sv));
    defer _ = std.c.close(sv[0]);
    defer _ = std.c.close(sv[1]);

    var conn: Conn = .{ .fd = sv[0] };

    // empty rbuf, idle socket: not readable
    try std.testing.expect(!(try conn.pollReadable(0)));

    // frame left fully buffered behind consumed bytes (two frames coalesced
    // in one TCP segment): readable even with nothing pending on the socket
    conn.rhead = 7;
    const fr = [_]u8{ 0x02, 4, 0, 0, 0, 0xaa, 0xbb, 0xcc, 0xdd };
    @memcpy(conn.rbuf[conn.rhead..][0..fr.len], &fr);
    conn.rtail = conn.rhead + fr.len;
    try std.testing.expect(try conn.pollReadable(0));

    // partial payload: not readable — readMessage would block in
    // ensureBuffered waiting for the rest, so the socket stays the arbiter
    conn.rtail = conn.rhead + fr.len - 1;
    try std.testing.expect(!(try conn.pollReadable(0)));

    // partial header: same
    conn.rtail = conn.rhead + 3;
    try std.testing.expect(!(try conn.pollReadable(0)));

    // bad header readMessage will reject: readable so the error surfaces
    // instead of stalling
    std.mem.writeInt(u32, conn.rbuf[conn.rhead + 1 ..][0..4], max_payload + 1, .little);
    conn.rtail = conn.rhead + 5;
    try std.testing.expect(try conn.pollReadable(0));

    // socket path with rbuf drained
    conn.rhead = 0;
    conn.rtail = 0;
    _ = std.c.write(sv[1], &fr, fr.len);
    try std.testing.expect(try conn.pollReadable(0));
}
