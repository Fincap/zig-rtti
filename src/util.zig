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
///
/// SAFETY: no validation is done on the given length, and the returned slice is not guaranteed to
/// point to valid memory.
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

test "makeSlice" {
    const testing = std.testing;
    const slice_data: []const u8 = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0xFA, 0xCE };
    const slice_start: [*]const u8 = @ptrCast(slice_data);
    const slice_len = 4;
    const new_slice = makeSlice(u8, slice_start, slice_len);
    try testing.expectEqual(new_slice.ptr, slice_start);
    try testing.expectEqual(new_slice.len, slice_len);
    try testing.expectEqualSlices(u8, slice_data[0..slice_len], new_slice);
}

test "isPointerSized" {
    const testing = std.testing;
    try testing.expect(!isPointerSized(i1));
    try testing.expect(!isPointerSized(i32));
    try testing.expect(!isPointerSized(i64));

    try testing.expect(!isPointerSized(u1));
    try testing.expect(!isPointerSized(u32));
    try testing.expect(!isPointerSized(u64));

    try testing.expect(isPointerSized(isize));
    try testing.expect(isPointerSized(usize));
}

test "hasMethod" {
    const testing = std.testing;
    const S = struct {
        pub fn testMethod() void {}
    };
    const E = enum(u8) {
        _,
        pub fn testMethod() void {}
    };
    const U = union {
        _: void,
        pub fn testMethod() void {}
    };
    try testing.expect(hasMethod(S, "testMethod"));
    try testing.expect(!hasMethod(S, "noMethod"));
    try testing.expect(hasMethod(E, "testMethod"));
    try testing.expect(!hasMethod(E, "noMethod"));
    try testing.expect(hasMethod(U, "testMethod"));
    try testing.expect(!hasMethod(U, "noMethod"));

    try testing.expect(!hasMethod(i32, "testMethod"));
    try testing.expect(!hasMethod(bool, "testMethod"));
}
