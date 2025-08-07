const std = @import("std");
const Allocator = std.mem.Allocator;

const RTTIError = @import("root.zig").RTTIError;

pub const TypeId = usize;

/// TODO: docs
pub fn typeId(comptime T: type) TypeId {
    const H = struct {
        var byte: u8 = 0;
        var _ = T;
    };
    return @intFromPtr(&H.byte);
}

/// Runtime equivalent of `std.builtin.Type`.
///
/// Excludes any comptime types that cannot be meaningfully represent at runtime.
///
/// TODO: maybe move the Type classes into this struct's namespace, mirroring std.
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
            else => {},
        }
    }
};

/// Runtime equivalent of `std.builtin.Type.Int`.
pub const Int = struct {
    // TODO
    signedness: Signedness,
    bits: u16,
};

/// Runtime equivalent of `std.builtin.Type.Float`.
pub const Float = struct {
    // TODO
    bits: u16,
};

/// Runtime equivalent of `std.builtin.Type.Pointer`.
pub const Pointer = struct {
    // TODO
    size: Size,
    is_const: bool,
    alignment: u16,
    child: *Type, // maybe a string instead?

    pub const Size = enum(u2) {
        one,
        many,
        slice,
        c,
    };
};

/// Runtime equivalent of `std.builtin.Type.Array`.
pub const Array = struct {
    // TODO
    len: usize,
    child: *Type, // maybe a string instead?
};

/// Runtime equivalent of `std.builtin.Type.Struct`.
///
/// Lacking fields from comptime (I'm open to adding them):
/// - `layout`: `ContainerLayout`
/// - `backing_integer`: `?type`
/// - `is_tuple`: `bool`
///
/// Runtime-exclusive fields:
/// - `size`: `usize`
/// - `alignment`: `usize`
///
/// Allocated fields will be owned by the `TypeRegistry` that created this struct, unless it was
/// manually created by the user.
pub const Struct = struct {
    const Self = @This();

    name: []const u8,
    fields: []const StructField,
    decls: []const Declaration,
    size: usize,
    alignment: usize,

    pub fn init(comptime T: type, allocator: Allocator) !Self {
        const struct_info = @typeInfo(T).@"struct";
        const fields = try allocator.alloc(StructField, struct_info.fields.len);
        inline for (struct_info.fields, 0..) |field, i| {
            fields[i] = StructField{
                .name = field.name,
                .type_name = @typeName(field.type),
                .default_value_ptr = field.default_value_ptr,
                .size = @sizeOf(field.type),
                .alignment = field.alignment,
                .offset = @offsetOf(T, field.name),
            };
        }
        const decls = try allocator.alloc(Declaration, struct_info.decls.len);
        inline for (struct_info.decls, 0..) |decl, i| {
            decls[i] = Declaration{ .name = decl.name };
        }
        return Self{
            .name = @typeName(T),
            .fields = fields,
            .decls = decls,
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.fields);
        allocator.free(self.decls);
    }

    pub fn getFieldPtr(self: *const Self, struct_ptr: *anyopaque, field_name: []const u8) ?*anyopaque {
        if (self.getFieldIndex(field_name)) |i| {
            const field = self.fields[i];
            return @ptrFromInt(@intFromPtr(struct_ptr) + field.offset);
        }
        return null;
    }

    pub fn getFieldSlice(self: *const Self, struct_ptr: *anyopaque, field_name: []const u8) ?[]const u8 {
        if (self.getFieldIndex(field_name)) |i| {
            return self.getFieldSliceIndexed(struct_ptr, i);
        }
        return null;
    }

    pub fn getFieldSliceIndexed(self: *const Self, struct_ptr: *const anyopaque, field_index: usize) []const u8 {
        const field = self.fields[field_index];
        const field_address = @intFromPtr(struct_ptr) + field.offset;
        var slice: []const u8 = undefined;
        slice.ptr = @ptrFromInt(field_address);
        slice.len = field.size;
        return slice;
    }

    /// O(n) search.
    pub fn getFieldIndex(self: *const Self, field_name: []const u8) ?usize {
        for (self.fields, 0..) |field, i| {
            if (std.mem.eql(u8, field_name, field.name)) {
                return i;
            }
        }
        return null;
    }

    pub fn getSlice(self: *const Self, struct_ptr: *anyopaque) []const u8 {
        var slice: []const u8 = undefined;
        slice.ptr = @ptrCast(@alignCast(struct_ptr));
        slice.len = self.size;
        return slice;
    }

    pub fn format(self: Struct, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = .{ fmt, options };
        try writer.print("{}{{ .name = \"{s}\", .size = {d}, .alignment = {d}, .fields = {{ ", .{ Struct, self.name, self.size, self.alignment });
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
    const Self = @This();

    name: []const u8,
    type_name: []const u8, // TODO: rather than pointing to a string, keep an ID to an interned arena?
    default_value_ptr: ?*const anyopaque,
    size: usize,
    alignment: usize,
    offset: usize,

    pub fn format(self: StructField, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = .{ fmt, options };
        try writer.print("{}{{ .name = \"{s}\", .type_name = \"{s}\", .default_value_ptr = {*}, size = {d}, alignment = {d}, offset = {d} }}", .{ StructField, self.name, self.type_name, self.default_value_ptr, self.size, self.alignment, self.offset });
    }
};

/// Runtime equivalent of `std.builtin.Type.Declaration`.
pub const Declaration = struct {
    const Self = @This();

    name: []const u8,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = .{ fmt, options };
        try writer.print("{}{{ .name = \"{s}\" }}", .{ Self, self.name });
    }
};

/// Runtime equivalent of `std.builtin.Type.Optional`.
pub const Optional = struct {
    // TODO
    child: *Type, // maybe a string instead?
};

/// Runtime equivalent of `std.builtin.Type.Enum`.
pub const Enum = struct {
    // TODO
    tag_type: *Type, // maybe a string instead?
    fields: []const EnumField,
    decls: []const Declaration,
};

pub const EnumField = struct {
    // TODO
    name: [:0]const u8,
    value: u64, // uncertain
};

/// Runtime equivalent of `std.builtin.Type.Union`.
pub const Union = struct {
    // TODO
};

/// Runtime equivalent of `std.builtin.Type.Fn`.
pub const Fn = struct {
    // TODO
};

/// Runtime equivalent of `std.builtin.Type.Signedness`.
pub const Signedness = enum {
    signed,
    unsigned,
};

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

pub fn runtimeSizeOf(type_name: []const u8) ?usize {
    const int_variants = @typeInfo(@TypeOf(numeric_types)).@"struct".fields;
    inline for (int_variants) |type_info| {
        const T: type = @field(numeric_types, type_info.name);
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

pub inline fn hasMethod(comptime T: type, comptime method: []const u8) bool {
    return @hasDecl(T, method) and @typeInfo(@TypeOf(@field(T, method))) == .@"fn";
}
