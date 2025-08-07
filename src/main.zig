const std = @import("std");
const my_float: f16 = std.math.pi;

const zrtti = @import("root.zig");
const fmt = zrtti.fmt;
const type_info = zrtti.type_info;
const TypeRegistry = zrtti.TypeRegistry;
const util = zrtti.util;

const OtherStruct = struct {
    pointer: *const f16 = &my_float,
};

const TestStruct = struct {
    // text: []const u8 = "my string",
    num: f16 = my_float,
    int: i32 = -132,
    other: OtherStruct = .{},
    // maybe: ?bool = true,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var registry = TypeRegistry.init(allocator);
    defer registry.deinit();
    const my_struct = TestStruct{};
    const info = try registry.registerType(TestStruct);
    try fmt.tryFormatStruct(&registry, &info.@"struct", &my_struct, std.io.getStdOut().writer().any());
    // std.debug.print("\n{}", .{info.*});
}
