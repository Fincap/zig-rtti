const std = @import("std");

const rtti = @import("root.zig");
const RTTIError = rtti.RTTIError;
const Type = rtti.type_info.Type;
const TypeRegistry = rtti.TypeRegistry;
const util = rtti.util;

pub const CustomFormatter = *const fn (struct_ptr: *const anyopaque, writer: std.io.AnyWriter) RTTIError!void;

pub fn tryFormatStruct(registry: *const TypeRegistry, info: *const Type.Struct, ptr: *const anyopaque, writer: std.io.AnyWriter) RTTIError!void {
    for (info.fields, 0..) |field_info, i| {
        const field_slice = info.getFieldSliceIndexed(ptr, i);
        const option_prefix = if (field_info.type.* == .optional) "?" else "";
        writer.print("{s}{s}: ", .{ field_info.name, option_prefix }) catch return error.FormatError;
        try tryFormatField(registry, &field_info, field_slice, writer);
        if (i < info.fields.len - 1) writer.writeAll(", ") catch return error.FormatError;
    }
}

pub fn tryFormatField(registry: *const TypeRegistry, info: *const Type.StructField, slice: []const u8, writer: std.io.AnyWriter) RTTIError!void {
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
        .int => |*t| {
            const int_types = @typeInfo(@TypeOf(util.integer_types)).@"struct".fields;
            inline for (int_types) |int_type| {
                const T: type = @field(util.integer_types, int_type.name);
                const int_info = @typeInfo(T).int;
                if (t.bits == int_info.bits and t.signedness == int_info.signedness and t.is_pointer_sized == util.isPointerSized(T)) {
                    const number = util.numberFromBytes(T, slice);
                    writer.print("{d}", .{number}) catch return error.FormatError;
                    break;
                }
            }
        },
        .float => |*t| {
            const float_types = @typeInfo(@TypeOf(util.float_types)).@"struct".fields;
            inline for (float_types) |float_type| {
                const T: type = @field(util.float_types, float_type.name);
                const float_info = @typeInfo(T).float;
                if (t.bits == float_info.bits) {
                    const number = util.numberFromBytes(T, slice);
                    writer.print("{d}", .{number}) catch return error.FormatError;
                    break;
                }
            }
        },
        .pointer => |*t| {
            switch (t.size) {
                .one, .c => {
                    const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
                    const len = t.child.size();
                    const inner_slice = util.makeSlice(u8, ptr, len);
                    writer.writeAll("*") catch return error.FormatError;
                    try formatSlice(registry, t.child, inner_slice, writer);
                },
                .slice => {
                    const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
                    const len = util.numberFromBytes(usize, slice[8..16]);

                    if (std.mem.eql(u8, t.child.typeName(), "u8")) {
                        // Format string
                        const string = util.makeSlice(u8, ptr, len);
                        writer.print("\"{s}\"", .{string}) catch return error.FormatError;
                    } else {
                        // Format array
                        const size = t.child.size();
                        const array_end = len * size;
                        var i: usize = 0;
                        writer.writeAll("{") catch return error.FormatError;
                        while (i < array_end) {
                            try formatSlice(registry, t.child, util.makeSlice(u8, ptr + i, size), writer);
                            if (i < (len - 1) * size) writer.writeAll(", ") catch return error.FormatError;
                            i += size;
                        }
                        writer.writeAll("}") catch return error.FormatError;
                    }
                },
                .many => {
                    @panic("unimplemented");
                },
            }
        },
        .array => |*t| {
            const size = t.child.size();
            const array_end = t.len * size;
            var i: usize = 0;
            writer.writeAll("{") catch return error.FormatError;
            while (i < array_end) {
                try formatSlice(registry, t.child, util.makeSlice(u8, slice.ptr + i, size), writer);
                if (i < (t.len - 1) * size) writer.writeAll(", ") catch return error.FormatError;
                i += size;
            }
            writer.writeAll("}") catch return error.FormatError;
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
        .@"enum" => |*t| {
            const size = t.tag_type.size();
            if (size > 8) @panic("enum tags greater than 64 bits unsupported");
            var value: u64 = 0;
            std.mem.copyForwards(u8, std.mem.asBytes(&value), slice[0..size]); // TODO: test if works on big-endian
            const variant = t.getNameFromValue(value).?;
            writer.print("{s}.{s}", .{ t.name, variant }) catch return error.FormatError;
        },
        .@"union" => |*t| {
            const variant_offset = t.size / 2;
            var variant: usize = 0;
            std.mem.copyForwards(u8, std.mem.asBytes(&variant), slice[variant_offset..]); // TODO: test if works on big-endian
            const active_field = t.fields[variant];
            writer.print("{s}.{s}", .{ t.name, active_field.name }) catch return error.FormatError;
            if (active_field.type) |field_type| {
                writer.writeAll("(") catch return error.FormatError;
                try formatSlice(registry, field_type, slice[0..variant_offset], writer);
                writer.writeAll(")") catch return error.FormatError;
            }
        },
        .@"fn" => {
            @panic("unimplemented");
        },
    }
}
