const std = @import("std");

const type_info = @import("type_info.zig");
const Struct = type_info.Struct;
const StructField = type_info.StructField;

pub inline fn numberFromBytes(comptime T: type, slice: []const u8) T {
    const bytes: *const [@sizeOf(T)]u8 = @ptrCast(@alignCast(slice));
    return @bitCast(bytes.*);
}

pub inline fn makeSlice(comptime T: type, ptr: [*]const T, len: usize) []const T {
    return @as([]const T, ptr[0..len]);
}
