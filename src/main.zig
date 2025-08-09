const std = @import("std");
const my_float: f16 = std.math.pi;

const zrtti = @import("root.zig");
const fmt = zrtti.fmt;
const type_info = zrtti.type_info;
const TypeRegistry = zrtti.TypeRegistry;
const util = zrtti.util;

const MyEnum = enum {
    one,
    two,
    three,
};

const MyUnion = union(enum) {
    ok: u32,
    not_ok,
};

const OtherStruct = struct {
    pointer: *const f16 = &my_float,
};

const TestStruct = struct {
    text: []const u8 = "my string",
    slice: []const u16 = &[_]u16{ 12, 14, 16, 11, 154 },
    num: f16 = my_float,
    int: i32 = -132,
    other: OtherStruct = .{},
    maybe: ?bool = null,
    array: [4]i8 = [4]i8{ -10, -1, 1, 10 },
    my_enum: MyEnum = .three,
    my_union: MyUnion = .{ .ok = 55 },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    // const union_info = @typeInfo(MyUnion).@"union";
    // const tag_size = if (union_info.tag_type) |tag| @sizeOf(tag) else 0;
    // std.debug.print("size = {d}, tag_type = {?}, tag_size = {d}, fields = {{ ", .{ @sizeOf(MyUnion), union_info.tag_type, tag_size });
    // inline for (union_info.fields, 0..) |field, i| {
    //     std.debug.print("{{ {s}: {} (.alignment = {d}) }}", .{ field.name, field.type, field.alignment });
    //     if (i < union_info.fields.len - 1) {
    //         std.debug.print(", ", .{});
    //     }
    // }
    // std.debug.print(" }}, decls = {{ ", .{});
    // inline for (union_info.decls, 0..) |decl, i| {
    //     std.debug.print("\"{s}\"", .{decl.name});
    //     if (i < union_info.decls.len - 1) {
    //         std.debug.print(", ", .{});
    //     }
    // }
    // std.debug.print(" }}\n", .{});

    // const my_union = MyUnion{ .ok = 0xFF };
    // const size = @sizeOf(MyUnion);
    // const raw_union: [*]const u8 = @ptrCast(&my_union);
    // const union_bytes: []const u8 = @ptrCast(raw_union[0..size]);
    // std.debug.print("size = {d}, bytes = {any}\n", .{ size, union_bytes });

    var registry = TypeRegistry.init(allocator);
    defer registry.deinit();
    const my_struct = TestStruct{};
    const info = try registry.registerType(TestStruct);
    try fmt.tryFormatStruct(&registry, &info.@"struct", &my_struct, std.io.getStdOut().writer().any());
    // std.debug.print("\n{}", .{info.*});
}
