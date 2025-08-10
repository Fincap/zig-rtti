const std = @import("std");

const rtti = @import("root.zig");
const Type = rtti.type_info.Type;
const TypeRegistry = rtti.TypeRegistry;
const util = rtti.util;

pub fn tryFormatStruct(registry: *const TypeRegistry, info: *const Type.Struct, ptr: *const anyopaque, writer: std.io.AnyWriter) anyerror!void {
    for (info.fields, 0..) |field_info, i| {
        const field_slice = info.getFieldSliceIndexed(ptr, i);
        const option_prefix = if (field_info.type.* == .optional) "?" else "";
        try writer.print("{s}{s}: ", .{ field_info.name, option_prefix });
        try tryFormatField(registry, &field_info, field_slice, writer);
        if (i < info.fields.len - 1) try writer.writeAll(", ");
    }
}

pub fn tryFormatField(registry: *const TypeRegistry, info: *const Type.StructField, slice: []const u8, writer: std.io.AnyWriter) anyerror!void {
    try formatSlice(registry, info.type, slice, writer);
}

pub fn formatSlice(registry: *const TypeRegistry, info: *const Type, slice: []const u8, writer: std.io.AnyWriter) anyerror!void {
    switch (info.*) {
        .bool => {
            const value = slice[0] != 0;
            try writer.print("{}", .{value});
        },
        .int => |*t| {
            const int_types = @typeInfo(@TypeOf(util.integer_types)).@"struct".fields;
            inline for (int_types) |int_type| {
                const T: type = @field(util.integer_types, int_type.name);
                const int_info = @typeInfo(T).int;
                if (t.bits == int_info.bits and t.signedness == int_info.signedness and t.is_pointer_sized == util.isPointerSized(T)) {
                    const number = util.numberFromBytes(T, slice);
                    try writer.print("{d}", .{number});
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
                    try writer.print("{d}", .{number});
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
                    try writer.writeAll("*");
                    try formatSlice(registry, t.child, inner_slice, writer);
                },
                .slice => {
                    const ptr: [*]const u8 = @ptrFromInt(util.numberFromBytes(usize, slice[0..8]));
                    const len = util.numberFromBytes(usize, slice[8..16]);

                    if (std.mem.eql(u8, t.child.typeName(), "u8")) {
                        // Format string
                        const string = util.makeSlice(u8, ptr, len);
                        try writer.print("\"{s}\"", .{string});
                    } else {
                        // Format array
                        const size = t.child.size();
                        const array_end = len * size;
                        var i: usize = 0;
                        try writer.writeAll("{");
                        while (i < array_end) {
                            try formatSlice(registry, t.child, util.makeSlice(u8, ptr + i, size), writer);
                            if (i < (len - 1) * size) try writer.writeAll(", ");
                            i += size;
                        }
                        try writer.writeAll("}");
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
            try writer.writeAll("{");
            while (i < array_end) {
                try formatSlice(registry, t.child, util.makeSlice(u8, slice.ptr + i, size), writer);
                if (i < (t.len - 1) * size) try writer.writeAll(", ");
                i += size;
            }
            try writer.writeAll("}");
        },
        .@"struct" => {
            try writer.writeAll("{ ");
            try tryFormatStruct(registry, &info.@"struct", @ptrCast(slice.ptr), writer);
            try writer.writeAll(" }");
        },
        .optional => |*t| {
            const option_offset: usize = info.size() / 2;
            const is_some = slice[option_offset] != 0;
            if (is_some) {
                try formatSlice(registry, t.child, slice[0..option_offset], writer);
            } else {
                try writer.writeAll("null");
            }
        },
        .@"enum" => |*t| {
            const size = t.tag_type.size();
            if (size > 8) @panic("enum tags greater than 64 bits unsupported");
            var value: u64 = 0;
            std.mem.copyForwards(u8, std.mem.asBytes(&value), slice[0..size]); // TODO: test if works on big-endian
            const variant = t.getNameFromValue(value).?;
            try writer.print("{s}.{s}", .{ t.name, variant });
        },
        .@"union" => |*t| {
            if (t.hasSafetyTag()) {
                const tag_offset = t.size / 2;
                var tag: usize = 0;
                std.mem.copyForwards(u8, std.mem.asBytes(&tag), slice[tag_offset..]); // TODO: test if works on big-endian
                const active_variant = t.fields[tag];
                try writer.print("{s}.{s}", .{ t.name, active_variant.name });
                if (active_variant.type) |field_type| {
                    try writer.writeAll("(");
                    try formatSlice(registry, field_type, slice[0..tag_offset], writer);
                    try writer.writeAll(")");
                }
            } else {
                try writer.print("{s}.unknown(", .{t.name});
                try formatSliceAsHex(slice, writer);
                try writer.writeAll(")");
            }
        },
        .@"fn" => {
            @panic("unimplemented");
        },
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
