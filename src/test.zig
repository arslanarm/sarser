const std = @import("std");
const sarser = @import("sarser.zig");

const Yes = union {
    integer: i32,
    float: f64
};

pub fn main() !void {
    var parser = try sarser.Sarser.init(std.testing.allocator);
    
    const value = try parser.parse(struct {
        a: ?Yes,
        b: f64,
        c: ?[]const u8,
        d: bool
    });
    try std.testing.expect(value.a.?.integer == 123);
    try std.testing.expect(value.b == 1.0);
    try std.testing.expect(std.mem.eql(u8, value.c.?, "yes"));
    try std.testing.expect(value.d);

    std.testing.allocator.free(value.c.?);
    parser.deinit();

    const leaks = std.testing.allocator_instance.detectLeaks();
    if (!leaks) std.log.info("Succesfully build a working library!!!", .{});
}