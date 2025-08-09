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
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    // const enum_info = @typeInfo(MyEnum).@"enum";
    // std.debug.print("tag_type = {}, fields = {{ ", .{enum_info.tag_type});
    // inline for (enum_info.fields, 0..) |field, i| {
    //     std.debug.print("{{ .name = {s}, .value = {d} }}", .{ field.name, field.value });
    //     if (i < enum_info.fields.len) {
    //         std.debug.print(", ", .{});
    //     }
    // }
    // std.debug.print(" }}, decls = {{ ", .{});
    // inline for (enum_info.decls, 0..) |decl, i| {
    //     std.debug.print("\"{s}\"", .{decl.name});
    //     if (i < enum_info.decls.len) {
    //         std.debug.print(", ", .{});
    //     }
    // }
    // std.debug.print(" }}\n", .{});

    // const my_enum = MyEnum.two;
    // const size = @sizeOf(MyEnum);
    // const raw_enum: [*]const u8 = @ptrCast(&my_enum);
    // const enum_bytes: []const u8 = @ptrCast(raw_enum[0..size]);
    // std.debug.print("size = {d}, bytes = {any}\n", .{ size, enum_bytes });

    var registry = TypeRegistry.init(allocator);
    defer registry.deinit();
    const my_struct = TestStruct{};
    const info = try registry.registerType(TestStruct);
    try fmt.tryFormatStruct(&registry, &info.@"struct", &my_struct, std.io.getStdOut().writer().any());
    // std.debug.print("\n{}", .{info.*});
}
