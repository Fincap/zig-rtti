const std = @import("std");
const builtin = @import("builtin");

pub const fmt = @import("fmt.zig");
pub const type_info = @import("type_info.zig");
pub const Type = type_info.Type;
pub const TypeRegistry = @import("type_registry.zig").TypeRegistry;
pub const util = @import("util.zig");

pub const RTTIError = error{
    InvalidField,
    FormatError,
};

const TestUnion = union(enum) {
    a: u8,
    b: u16,
    c: u32,
    d: u32,
    e: void,
};

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

pub fn main() !void {
    std.debug.print("Optimize mode: {}\n", .{builtin.mode});
    printEnumInfo(TestUnion);
}

test {
    std.testing.refAllDecls(@This());
}
