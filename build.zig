const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const tst = b.addTest("src/sarser.zig");
    const tst_exe = b.addExecutable("test", "src/test.zig");
    const run = tst_exe.run();

    run.addArgs(&[_][]const u8{
        "--a=123",
        "1.0",
        "--c=yes",
        "true"
    });

    const test_step = b.step("test", "Runs the test suite.");
    test_step.dependOn(&tst.step);
    test_step.dependOn(&run.step);
}


pub fn addTo(step: *std.build.LibExeObjStep, comptime libLocation: []const u8) void {
    step.addPackagePath("sarser", libLocation ++ "/src/sarser.zig");
}