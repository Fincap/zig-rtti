const std = @import("std");

const RTTIError = @import("root.zig").RTTIError;
const type_info = @import("type_info.zig");
const Struct = type_info.Struct;
const StructField = type_info.StructField;
const Type = type_info.Type;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const util = @import("util.zig");

pub const CustomFormatter = *const fn (struct_ptr: *const anyopaque, writer: std.io.AnyWriter) RTTIError!void;

pub fn tryFormatStruct(registry: *const TypeRegistry, info: *const Struct, ptr: *const anyopaque, writer: std.io.AnyWriter) RTTIError!void {
    for (info.fields, 0..) |field_info, i| {
        const field_slice = info.getFieldSliceIndexed(ptr, i);
        const option_prefix = if (field_info.type.* == .optional) "?" else "";
        writer.print("{s}{s}: ", .{ field_info.name, option_prefix }) catch return error.FormatError;
        try tryFormatField(registry, &field_info, field_slice, writer);
        if (i < info.fields.len - 1) writer.writeAll(", ") catch return error.FormatError;
    }
}

pub fn tryFormatField(registry: *const TypeRegistry, info: *const StructField, slice: []const u8, writer: std.io.AnyWriter) RTTIError!void {
    try formatSlice(registry, info.type, slice, writer);
}

pub fn formatSlice(registry: *const TypeRegistry, info: *const Type, slice: []const u8, writer: std.io.AnyWriter) RTTIError!void {
    // Custom formatter
    if (registry.getTypeId(info.typeName())) |type_id| {
        if (registry.formatters.get(type_id)) |formatter| {
            try formatter(slice.ptr, writer);
            return;
        }
    }

    switch (info.*) {
        .bool => {
            const value = slice[0] != 0;
            writer.print("{}", .{value}) catch return error.FormatError;
        },
        .int, .float => {
            // const number = util.numberFromBytes(T, slice);
            // writer.print("{d}", .{number}) catch return error.FormatError;
        },
        .pointer => |*t| {
            _ = t;
            // const pointee_name = if (std.mem.startsWith(u8, type_name[1..], "const ")) type_name[7..] else type_name[1..];
            // const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
            // const len = type_info.runtimeSizeOf(pointee_name).?;
            // const inner_slice = util.makeSlice(u8, ptr, len);
            // writer.writeAll("*") catch return error.FormatError;
            // try formatSlice(registry, pointee_name, inner_slice, writer);
        },
        .array => |*t| {
            _ = t;
            // const pointee_name = if (std.mem.startsWith(u8, type_name[2..], "const ")) type_name[8..] else type_name[2..];
            // const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
            // const len = util.numberFromBytes(usize, slice[8..16]);
            // const size = type_info.runtimeSizeOf(pointee_name).?;
            // const array_end = len * size;
            // var i: usize = 0;
            // writer.writeAll("{") catch return error.FormatError;
            // while (i < array_end) {
            //     try formatSlice(registry, pointee_name, util.makeSlice(u8, ptr + i, size), writer);
            //     if (i < (len - 1) * size) writer.writeAll(", ") catch return error.FormatError;
            //     i += size;
            // }
            // writer.writeAll("}") catch return error.FormatError;
        },
        .@"struct" => {
            writer.writeAll("{ ") catch return error.FormatError;
            try tryFormatStruct(registry, &info.@"struct", @ptrCast(slice.ptr), writer);
            writer.writeAll(" }") catch return error.FormatError;
        },
        .optional => |*t| {
            const option_offset: usize = info.size() / 2;
            const is_some = slice[option_offset] != 0;
            if (is_some) {
                try formatSlice(registry, t.child, slice[0..option_offset], writer);
            } else {
                writer.writeAll("null") catch return error.FormatError;
            }
        },
        .@"enum" => {},
        .@"union" => {},
        .@"fn" => {},
    }
}

pub fn formatSliceOld(registry: *const TypeRegistry, type_name: []const u8, slice: []const u8, writer: std.io.AnyWriter) RTTIError!void {
    if (registry.getTypeId(type_name)) |type_id| {
        // Custom formatter
        if (registry.formatters.get(type_id)) |formatter| {
            try formatter(@ptrCast(slice.ptr), writer);
            return;
        }

        // Format struct
        if (registry.getTypeInfo(type_name)) |info| {
            if (info.* == .@"struct") {
                writer.writeAll("{ ") catch return error.FormatError;
                try tryFormatStruct(registry, &info.@"struct", @ptrCast(slice.ptr), writer);
                writer.writeAll(" }") catch return error.FormatError;
                return;
            }
        }
    }

    // Format number
    const int_variants = @typeInfo(@TypeOf(type_info.numeric_types)).@"struct".fields;
    inline for (int_variants) |info| {
        const T: type = @field(type_info.numeric_types, info.name);
        if (std.mem.eql(u8, type_name, @typeName(T))) {
            const number = util.numberFromBytes(T, slice);
            writer.print("{d}", .{number}) catch return error.FormatError;
            return;
        }
    }

    // Format bool
    if (std.mem.eql(u8, type_name, "bool")) {
        const value = slice[0] != 0;
        writer.print("{}", .{value}) catch return error.FormatError;
        return;
    }

    // Format string
    if (std.mem.eql(u8, type_name, "[]const u8")) {
        const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
        const len = util.numberFromBytes(usize, slice[8..16]);
        const string = util.makeSlice(u8, ptr, len);
        writer.print("\"{s}\"", .{string}) catch return error.FormatError;
        return;
    }

    // Format pointer
    if (type_info.isPointer(type_name)) {
        const pointee_name = if (std.mem.startsWith(u8, type_name[1..], "const ")) type_name[7..] else type_name[1..];
        const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
        const len = type_info.runtimeSizeOf(pointee_name).?;
        const inner_slice = util.makeSlice(u8, ptr, len);
        writer.writeAll("*") catch return error.FormatError;
        try formatSlice(registry, pointee_name, inner_slice, writer);
        return;
    }

    // Format array
    if (type_info.isSlice(type_name)) {
        const pointee_name = if (std.mem.startsWith(u8, type_name[2..], "const ")) type_name[8..] else type_name[2..];
        const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
        const len = util.numberFromBytes(usize, slice[8..16]);
        const size = type_info.runtimeSizeOf(pointee_name).?;
        const array_end = len * size;
        var i: usize = 0;
        writer.writeAll("{") catch return error.FormatError;
        while (i < array_end) {
            try formatSlice(registry, pointee_name, util.makeSlice(u8, ptr + i, size), writer);
            if (i < (len - 1) * size) writer.writeAll(", ") catch return error.FormatError;
            i += size;
        }
        writer.writeAll("}") catch return error.FormatError;
        return;
    }

    // Format optional
    if (type_info.isOptional(type_name)) {
        const optional_size = type_info.runtimeSizeOf(type_name).?;
        const option_offset: usize = optional_size / 2;
        const is_some = slice[option_offset] != 0;
        if (is_some) {
            try formatSlice(registry, type_name[1..], slice[0..option_offset], writer);
        } else {
            writer.writeAll("null") catch return error.FormatError;
        }
        return;
    }

    // if all else fails, format as byte array
    writer.print("!{s}{any}", .{ type_name, slice }) catch return error.FormatError;
}
