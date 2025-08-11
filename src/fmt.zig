const std = @import("std");

const rtti = @import("root.zig");
const Type = rtti.Type;
const TypeRegistry = rtti.TypeRegistry;
const util = rtti.util;

pub fn formatType(
    info: *const Type,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    switch (info.*) {
        .bool => try formatBool(erased, writer),
        .int => |*t| try formatInt(t, erased, writer),
        .float => |*t| try formatFloat(t, erased, writer),
        .pointer => |*t| try formatPointer(t, erased, writer),
        .array => |*t| try formatArray(t.child, erased, t.len, writer),
        .@"struct" => |*t| try formatStruct(t, erased, writer),
        .optional => |*t| try formatOptional(t, erased, writer),
        .@"enum" => |*t| try formatEnum(t, erased, writer),
        .@"union" => |*t| try formatUnion(t, erased, writer),
        .@"fn" => {
            @panic("unimplemented");
        },
    }
}

pub fn formatBool(
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const bool_ptr: *const bool = @ptrCast(erased);
    try writer.print("{}", .{bool_ptr.*});
}

pub fn formatInt(
    info: *const Type.Int,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const slice = util.makeSlice(u8, @ptrCast(erased), info.size());
    const int_types = @typeInfo(@TypeOf(util.integer_types)).@"struct".fields;
    inline for (int_types) |int_type| {
        const T: type = @field(util.integer_types, int_type.name);
        const T_info = @typeInfo(T).int;
        if (info.bits == T_info.bits and info.signedness == T_info.signedness and info.is_pointer_sized == util.isPointerSized(T)) {
            const number = std.mem.bytesToValue(T, slice);
            try writer.print("{d}", .{number});
            break;
        }
    }
}

pub fn formatFloat(
    info: *const Type.Float,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const slice = util.makeSlice(u8, @ptrCast(erased), info.size());
    const float_types = @typeInfo(@TypeOf(util.float_types)).@"struct".fields;
    inline for (float_types) |float_type| {
        const T: type = @field(util.float_types, float_type.name);
        const T_info = @typeInfo(T).float;
        if (info.bits == T_info.bits) {
            const number = std.mem.bytesToValue(T, slice);
            try writer.print("{d}", .{number});
            break;
        }
    }
}

pub fn formatPointer(
    info: *const Type.Pointer,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const slice = util.makeSlice(u8, @ptrCast(erased), info.sizeInBytes());
    const child_ptr: [*]const u8 = @ptrFromInt(std.mem.bytesToValue(usize, slice[0..8]));
    switch (info.size) {
        .one, .c => {
            try writer.writeAll("*");
            try formatType(info.child, child_ptr, writer);
        },
        .slice => {
            const len = std.mem.bytesToValue(usize, slice[8..16]);
            if (std.mem.eql(u8, info.child.typeName(), "u8")) {
                // Interpret u8 slice as string
                const string = util.makeSlice(u8, child_ptr, len);
                try writer.print("\"{s}\"", .{string});
            } else {
                try formatArray(info.child, child_ptr, len, writer);
            }
        },
        .many => {
            @panic("unimplemented"); // depends on adding `sentinel_ptr` to `Type.Pointer`
        },
    }
}

pub fn formatArray(
    child_type: *const Type,
    ptr: *const anyopaque,
    len: usize,
    writer: std.io.AnyWriter,
) anyerror!void {
    const array_ptr: [*]const u8 = @ptrCast(ptr);
    const elem_size = child_type.size();
    const array_end = len * elem_size;
    var i: usize = 0;
    try writer.writeAll("{");
    while (i < array_end) {
        try formatType(child_type, array_ptr + i, writer);
        if (i < (len - 1) * elem_size) try writer.writeAll(", ");
        i += elem_size;
    }
    try writer.writeAll("}");
}

pub fn formatStruct(
    info: *const Type.Struct,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    try writer.writeAll("{ ");
    for (info.fields, 0..) |field_info, i| {
        const field_ptr = info.getFieldPtrIndexed(erased, i);
        const option_prefix = if (field_info.type.* == .optional) "?" else "";
        try writer.print("{s}{s}: ", .{ field_info.name, option_prefix });
        try formatType(field_info.type, field_ptr, writer);
        if (i < info.fields.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll(" }");
}

pub fn formatOptional(
    info: *const Type.Optional,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const slice = util.makeSlice(u8, @ptrCast(erased), info.size());
    const option_offset: usize = info.size() / 2;
    const is_some = slice[option_offset] != 0;
    if (is_some) {
        try formatType(info.child, erased, writer);
    } else {
        try writer.writeAll("null");
    }
}

pub fn formatEnum(
    info: *const Type.Enum,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const size = info.size();
    if (size > 8) @panic("enum tags greater than 64 bits unsupported");
    const slice = util.makeSlice(u8, @ptrCast(erased), size);
    var value: u64 = 0;
    std.mem.copyForwards(u8, std.mem.asBytes(&value), slice[0..size]); // TODO: test if works on big-endian
    const variant = info.getNameFromValue(value).?;
    try writer.print("{s}.{s}", .{ info.name, variant });
}

pub fn formatUnion(
    info: *const Type.Union,
    erased: *const anyopaque,
    writer: std.io.AnyWriter,
) anyerror!void {
    const slice = util.makeSlice(u8, @ptrCast(erased), info.size);
    if (info.hasSafetyTag()) {
        const tag_offset = info.size / 2;
        var tag: usize = 0;
        std.mem.copyForwards(u8, std.mem.asBytes(&tag), slice[tag_offset..]); // TODO: test if works on big-endian
        const active_variant = info.fields[tag];
        try writer.print("{s}.{s}", .{ info.name, active_variant.name });
        if (active_variant.type) |field_type| {
            try writer.writeAll("(");
            try formatType(field_type, erased, writer);
            try writer.writeAll(")");
        }
    } else {
        try writer.print("{s}.unknown(", .{info.name});
        try formatSliceAsHex(slice, writer);
        try writer.writeAll(")");
    }
}

pub fn formatSliceAsHex(slice: []const u8, writer: std.io.AnyWriter) anyerror!void {
    for (slice, 0..) |byte, i| {
        try writer.print("{X:0>2}", .{byte});
        if (i < slice.len - 1) {
            try writer.writeByte(' ');
        }
    }
}
