const std = @import("std");
const builtin = @import("builtin");

pub const fmt = @import("fmt.zig");
pub const type_info = @import("type_info.zig");
pub const Type = type_info.Type;
pub const TypeRegistry = @import("type_registry.zig").TypeRegistry;
pub const util = @import("util.zig");

fn printEnumInfo(comptime T: type) void {
    const info = @typeInfo(T).@"union";
    std.debug.print("---- {} ({?}) ----\n", .{ T, info.tag_type });
    std.debug.print("  size: {d}, alignment: {d}\n", .{ @sizeOf(T), @alignOf(T) });
    std.debug.print("  layout: {}\n", .{info.layout});
    std.debug.print("  fields:\n", .{});
    inline for (info.fields) |field| {
        std.debug.print("    {s} ({?}), size: {d}, alignment: {d}\n", .{ field.name, field.type, @sizeOf(field.type), field.alignment });
    }
}

const TestEnum = enum(u8) { a, b, c };

const TestUnion = union {
    float: f32,
    char: u8,
    empty: void,
};

const InnerStruct = struct {
    text: []const u8,
};

const TestStruct = struct {
    is_true: bool = false,
    number: i32 = 123,
    float: f16 = 9.99,
    pointer: *const f64 = &@as(f64, std.math.pi),
    array: [4]u8 = [_]u8{ 10, 9, 8, 7 },
    inner: InnerStruct = .{ .text = "test" },
    maybe: ?bool = null,
    test_enum: TestEnum = .c,
    test_union: TestUnion = .{ .char = 'x' },

    pub const my_decl = 0;
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var registry = TypeRegistry.init(allocator);
    defer registry.deinit();

    const test_struct = TestStruct{};
    const info = try registry.registerType(TestStruct);
    try fmt.formatType(&registry, info, &test_struct, std.io.getStdOut().writer().any());
}

test {
    std.testing.refAllDecls(@This());
}
