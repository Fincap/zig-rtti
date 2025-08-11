const std = @import("std");

/// Comptime tuple containing all built-in standard integer primitive types.
///
/// Can be used to implement a comptime iterator over integer types.
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

/// Comptime tuple containing all built-in floating point primitive types.
///
/// Can be used to implement a comptime iterator over float types.
pub const float_types = .{
    f16,
    f32,
    f64,
    f128,
};

/// Reinterprets the given `slice` argument into raw bytes representing the given type.
///
/// TODO: rename `reinterpretCast`?
pub inline fn numberFromBytes(comptime T: type, slice: []const u8) T {
    const bytes: *const [@sizeOf(T)]u8 = @ptrCast(@alignCast(slice));
    return @bitCast(bytes.*);
}

/// Casts a many-item pointer into a slice with the given length.
pub inline fn makeSlice(comptime T: type, ptr: [*]const T, len: usize) []const T {
    return @as([]const T, ptr[0..len]);
}

/// Test if the given type is pointer sized (i.e. is a `usize` or `isize`).
pub inline fn isPointerSized(comptime T: type) bool {
    return T == usize or T == isize;
}

/// Returns true if the given struct, enum, union or opaque has a method of the given name.
pub inline fn hasMethod(comptime T: type, comptime method: []const u8) bool {
    const t = @typeInfo(T);
    if (t != .@"struct" and t != .@"enum" and t != .@"union" and t != .@"opaque") return false;
    return @hasDecl(T, method) and @typeInfo(@TypeOf(@field(T, method))) == .@"fn";
}

/// For a given number of bits, returns the power-of-two number of bytes required to store a value
/// of the given bit width.
pub inline fn bitsToBytesCeil(bits: usize) usize {
    return (bits + 7) / 8;
}
