const std = @import("std");

pub const integer_types = .{
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
};

pub const float_types = .{
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
    const int_variants = @typeInfo(@TypeOf(integer_types)).@"struct".fields;
    inline for (int_variants) |info| {
        const T: type = @field(integer_types, info.name);
        if (std.mem.eql(u8, type_name, @typeName(T))) {
            return @sizeOf(T);
        }
    }
    const float_variants = @typeInfo(@TypeOf(float_types)).@"struct".fields;
    inline for (float_variants) |info| {
        const T: type = @field(float_types, info.name);
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

pub inline fn isPointerSized(comptime T: type) bool {
    return T == usize or T == isize;
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

pub inline fn hasMethod(comptime T: type, comptime method: []const u8) bool {
    const t = @typeInfo(T);
    if (t != .@"struct" and t != .@"enum" and t != .@"union" and t != .@"opaque") return false;
    return @hasDecl(T, method) and @typeInfo(@TypeOf(@field(T, method))) == .@"fn";
}
