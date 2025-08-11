const std = @import("std");
const Allocator = std.mem.Allocator;

const rtti = @import("root.zig");
const TypeRegistry = rtti.TypeRegistry;
const util = rtti.util;

/// Runtime equivalent of `std.builtin.Type`.
///
/// Excludes any comptime types that cannot be meaningfully represented at runtime.
pub const Type = union(enum) {
    bool: void,
    int: Int,
    float: Float,
    pointer: Pointer,
    array: Array,
    @"struct": Struct,
    optional: Optional,
    @"enum": Enum,
    @"union": Union,
    @"fn": Fn,

    pub fn deinit(self: *Type, allocator: Allocator) void {
        switch (self.*) {
            .@"struct" => |*t| t.deinit(allocator),
            .@"enum" => |*t| t.deinit(allocator),
            .@"union" => |*t| t.deinit(allocator),
            .@"fn" => |*t| t.deinit(allocator),
            else => {},
        }
    }

    pub fn typeName(self: Type) []const u8 {
        return switch (self) {
            .int => |t| t.typeName(),
            .float => |t| t.typeName(),
            .pointer => |t| t.name,
            .array => |t| t.name,
            .@"struct" => |t| t.name,
            .optional => |t| t.name,
            .@"enum" => |t| t.name,
            .@"union" => |t| t.name,
            else => @tagName(self),
        };
    }

    pub fn size(self: Type) usize {
        return switch (self) {
            .bool => @sizeOf(bool),
            .int => |t| t.size(),
            .float => |t| t.size(),
            .pointer => |t| t.sizeInBytes(),
            .array => |t| t.size(),
            .@"struct" => |t| t.size,
            .optional => |t| t.size(),
            .@"enum" => |t| t.size(),
            .@"union" => |t| t.size,
            .@"fn" => @panic("unimplemented!"),
        };
    }

    /// Runtime equivalent of `std.builtin.Type.Int`.
    pub const Int = struct {
        signedness: std.builtin.Signedness,
        bits: u16,
        is_pointer_sized: bool,

        pub fn typeName(self: Int) []const u8 {
            if (self.is_pointer_sized) {
                return if (self.signedness == .signed) @typeName(isize) else @typeName(usize);
            }
            return switch (self.bits) {
                8 => if (self.signedness == .signed) @typeName(i8) else @typeName(u8),
                16 => if (self.signedness == .signed) @typeName(i16) else @typeName(u16),
                32 => if (self.signedness == .signed) @typeName(i32) else @typeName(u32),
                64 => if (self.signedness == .signed) @typeName(i8) else @typeName(u8),
                128 => if (self.signedness == .signed) @typeName(i8) else @typeName(u8),
                else => @panic("arbitrary bit-width integers not supported"),
            };
        }

        pub fn size(self: Int) usize {
            return std.math.ceilPowerOfTwoAssert(usize, self.bits / 8);
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Float`.
    pub const Float = struct {
        bits: u16,

        pub fn typeName(self: Float) []const u8 {
            switch (self.bits) {
                16 => return @typeName(f16),
                32 => return @typeName(f32),
                64 => return @typeName(f64),
                80 => return @typeName(f80),
                128 => return @typeName(f128),
                else => @panic("unsupported float width"),
            }
        }

        pub fn size(self: Float) usize {
            return std.math.ceilPowerOfTwoAssert(usize, self.bits / 8);
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Pointer`.
    ///
    /// Fields excluded:
    /// - `is_volatile`: `bool`
    /// - `address_space`: `AddressSpace`
    /// - `is_allowzero`: `bool`
    /// - `sentinel_ptr`: `?*const anyopaque`
    ///
    /// e.g. []const u8 -> {size: .slice, is_const: true, alignment: 1, child: u8}
    pub const Pointer = struct {
        name: []const u8,
        size: Size,
        is_const: bool,
        alignment: u16,
        child: *Type,

        pub const Size = enum(u2) {
            one,
            many,
            slice,
            c,
        };

        pub fn sizeInBytes(self: Pointer) usize {
            return switch (self.size) {
                .slice => @sizeOf(usize) * 2,
                else => @sizeOf(usize),
            };
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Array`.
    ///
    /// Fields excluded:
    /// - `sentinel_ptr`: `?*const anyopaque`
    ///
    /// e.g. [5]u8 -> {len: 5, child: u8}
    pub const Array = struct {
        name: []const u8,
        len: usize,
        child: *Type,

        pub fn size(self: Array) usize {
            return self.len * self.child.size();
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Struct`.
    ///
    /// Fields excluded:
    /// - `layout`: `ContainerLayout`
    /// - `backing_integer`: `?type`
    /// - `is_tuple`: `bool`
    ///
    /// Allocated fields are be owned by the `TypeRegistry` that created this struct.
    pub const Struct = struct {
        name: []const u8,
        fields: []const StructField,
        decls: []const Declaration,
        size: usize,
        alignment: usize,

        pub fn deinit(self: *Struct, allocator: Allocator) void {
            allocator.free(self.fields);
            allocator.free(self.decls);
        }

        pub fn getFieldPtr(
            self: *const Struct,
            struct_ptr: *const anyopaque,
            field_name: []const u8,
        ) ?*anyopaque {
            if (self.getFieldIndex(field_name)) |i| {
                const field = self.fields[i];
                return @ptrFromInt(@intFromPtr(struct_ptr) + field.offset);
            }
            return null;
        }

        pub fn getFieldPtrIndexed(
            self: *const Struct,
            struct_ptr: *const anyopaque,
            field_index: usize,
        ) *anyopaque {
            const field = self.fields[field_index];
            const field_address = @intFromPtr(struct_ptr) + field.offset;
            return @ptrFromInt(field_address);
        }

        pub fn getFieldSlice(
            self: *const Struct,
            struct_ptr: *const anyopaque,
            field_name: []const u8,
        ) ?[]const u8 {
            if (self.getFieldIndex(field_name)) |i| {
                return self.getFieldSliceIndexed(struct_ptr, i);
            }
            return null;
        }

        pub fn getFieldSliceIndexed(
            self: *const Struct,
            struct_ptr: *const anyopaque,
            field_index: usize,
        ) []const u8 {
            const field = self.fields[field_index];
            const field_address = @intFromPtr(struct_ptr) + field.offset;
            return util.makeSlice(u8, @ptrFromInt(field_address), field.type.size());
        }

        /// O(n) search.
        pub fn getFieldIndex(self: *const Struct, field_name: []const u8) ?usize {
            for (self.fields, 0..) |field, i| {
                if (std.mem.eql(u8, field_name, field.name)) {
                    return i;
                }
            }
            return null;
        }

        pub fn getSlice(self: *const Struct, struct_ptr: *const anyopaque) []const u8 {
            return util.makeSlice(u8, struct_ptr, self.size);
        }

        pub fn format(
            self: Struct,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = .{ fmt, options };
            try writer.print(
                "{}{{ .name = \"{s}\", .size = {d}, .alignment = {d}, .fields = {{ ",
                .{ Struct, self.name, self.size, self.alignment },
            );
            for (self.fields, 0..) |field, i| {
                try writer.print("{}", .{field});
                if (i < self.fields.len - 1) try writer.writeAll(", ");
            }
            try writer.writeAll(" }, .decls = { ");
            for (self.decls, 0..) |decl, i| {
                try writer.print("{}", .{decl});
                if (i < self.fields.len - 1) try writer.writeAll(", ");
            }
            try writer.writeAll(" }");
        }
    };

    /// Runtime equivalent of `std.builtin.Type.StructField`.
    pub const StructField = struct {
        name: []const u8,
        type: *Type,
        default_value_ptr: ?*const anyopaque,
        alignment: usize,
        offset: usize,

        pub fn format(
            self: StructField,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = .{ fmt, options };
            try writer.print(
                "{}{{ .name = \"{s}\", .type_name = \"{s}\", .default_value_ptr = {*}, alignment = {d}, offset = {d} }}",
                .{ StructField, self.name, self.type.typeName(), self.default_value_ptr, self.alignment, self.offset },
            );
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Declaration`.
    pub const Declaration = struct {
        name: []const u8,

        pub fn format(
            self: Declaration,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = .{ fmt, options };
            try writer.print("{}{{ .name = \"{s}\" }}", .{ Declaration, self.name });
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Optional`.
    pub const Optional = struct {
        name: []const u8,
        child: *Type,

        pub fn size(self: Optional) usize {
            return self.child.size() * 2;
        }
    };

    /// Runtime equivalent of `std.builtin.Type.Enum`.
    ///
    /// Fields excluded:
    /// - `is_exhaustive`: `bool`
    ///
    /// Allocated fields are be owned by the `TypeRegistry` that created this struct.
    pub const Enum = struct {
        name: []const u8,
        tag_type: *Type,
        fields: []const EnumField,
        decls: []const Declaration,

        pub fn deinit(self: *Enum, allocator: Allocator) void {
            allocator.free(self.fields);
            allocator.free(self.decls);
        }

        pub fn getNameFromValue(self: Enum, value: u64) ?[]const u8 {
            for (self.fields) |field| {
                if (field.value == value) return field.name;
            }
            return null;
        }

        pub fn size(self: Enum) usize {
            return self.tag_type.size();
        }
    };

    /// Runtime equivalent of `std.builtin.Type.EnumField`.
    pub const EnumField = struct {
        name: []const u8,
        value: u64,
    };

    /// Runtime equivalent of `std.builtin.Type.Union`.
    ///
    /// Allocated fields are be owned by the `TypeRegistry` that created this struct.
    pub const Union = struct {
        name: []const u8,
        layout: std.builtin.Type.ContainerLayout,
        tag_type: ?*Type,
        fields: []const UnionField,
        decls: []const Declaration,
        size: usize,

        pub fn deinit(self: *Union, allocator: Allocator) void {
            allocator.free(self.fields);
            allocator.free(self.decls);
        }

        /// A regular union doesn’t have a guaranteed memory layout (a safety tag is added in debug
        /// and release safe mode).
        pub fn hasSafetyTag(self: Union) bool {
            return self.size == self.largestVariantSize() * 2;
        }

        /// Returns the size of the largest union variant. In untagged unions with no added safety
        /// tag,  this will be the size of the union.
        pub fn largestVariantSize(self: Union) usize {
            var max: usize = 0;
            for (self.fields) |field| {
                if (field.type) |field_type| {
                    const field_size = field_type.size();
                    if (field_size > max) max = field_size;
                }
            }
            return max;
        }
    };

    /// Runtime equivalent of `std.builtin.Type.UnionField`.
    pub const UnionField = struct {
        name: []const u8,
        type: ?*Type,
        alignment: usize,
    };

    /// Runtime equivalent of `std.builtin.Type.Fn`.
    ///
    /// Functions using generics or varargs are not supported.
    pub const Fn = struct {
        calling_convention: std.builtin.CallingConvention,
        return_type: ?*Type,
        params: []const *Type,

        pub fn deinit(self: *Fn, allocator: Allocator) void {
            allocator.free(self.params);
        }
    };
};

test "Type.Union layout" {
    // TODO: write tests
    // if Union.layout == packed, expect tag_type == null
    // if Union.layout == packed, expect Union.size == [largest field].size
    // if Union.tag_type != null, expect Union.size == [largest field].size * 2
}
