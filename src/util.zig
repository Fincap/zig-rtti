const std = @import("std");

const type_info = @import("type_info.zig");
const Struct = type_info.Struct;
const StructField = type_info.StructField;

pub const numeric_types = .{
    isize,
    i8,
    i16,
    i32,
    i64,
    i128,
    usize,
    u8,
    u16,
    u32,
    u64,
    u128,
    f16,
    f32,
    f64,
    f128,
};

pub inline fn numberFromBytes(comptime T: type, slice: []const u8) T {
    const bytes: *const [@sizeOf(T)]u8 = @ptrCast(@alignCast(slice));
    return @bitCast(bytes.*);
}

pub inline fn makeSlice(comptime T: type, ptr: [*]const T, len: usize) []const T {
    return @as([]const T, ptr[0..len]);
}

pub fn runtimeSizeOf(type_name: []const u8) ?usize {
    const int_variants = @typeInfo(@TypeOf(numeric_types)).@"struct".fields;
    inline for (int_variants) |info| {
        const T: type = @field(numeric_types, info.name);
        if (std.mem.eql(u8, type_name, @typeName(T))) {
            return @sizeOf(T);
        }
    }
    if (isPointer(type_name)) {
        return @sizeOf(usize);
    }
    if (isSlice(type_name)) {
        return 2 * @sizeOf(usize);
    }

    if (isOptional(type_name)) {
        if (runtimeSizeOf(type_name[1..])) |sub_size| {
            return 2 * sub_size;
        }
    }
    return null;
}

pub fn isPointer(type_name: []const u8) bool {
    return std.mem.startsWith(u8, type_name, "*");
}

pub fn isSlice(type_name: []const u8) bool {
    return std.mem.startsWith(u8, type_name, "[]");
}

pub fn isOptional(type_name: []const u8) bool {
    return std.mem.startsWith(u8, type_name, "?");
}
