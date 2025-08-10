const std = @import("std");
const Allocator = std.mem.Allocator;

const rtti = @import("root.zig");
const CustomFormatter = rtti.fmt.CustomFormatter;
const Type = rtti.Type;
const TypeId = rtti.type_info.TypeId;
const typeId = rtti.type_info.typeId;
const util = rtti.util;
const StableMap = @import("stable_map.zig").StableMap;

/// Registry of runtime information for types.
pub const TypeRegistry = struct {
    const Self = @This();

    allocator: Allocator,
    registered_types: TypeMap = .empty,
    type_names: std.StringHashMapUnmanaged(TypeId) = .empty,
    formatters: std.AutoHashMapUnmanaged(TypeId, CustomFormatter) = .empty,

    const TypeMap = StableMap(TypeId, Type, .{});

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        var iter_types = self.registered_types.iterator();
        while (iter_types.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.registered_types.deinit(self.allocator);
        self.type_names.deinit(self.allocator);
        self.formatters.deinit(self.allocator);
    }

    /// Registers the given type, and recursively registers the types of any child types (i.e.
    /// struct fields, pointer targets, ..)
    ///
    /// Pointers to returned struct is owned by the registry, and is expected to live for the
    /// remainder of the registry's lifetime.
    pub fn registerType(self: *Self, comptime T: type) !*Type {
        const type_id = typeId(T);
        const entry = try self.registered_types.getOrPut(self.allocator, type_id);
        if (entry.found_existing) {
            return entry.value_ptr;
        }

        // Map type name -> type ID
        const type_name = @typeName(T);
        try self.type_names.put(self.allocator, type_name, type_id);
        errdefer _ = self.type_names.remove(type_name);

        entry.value_ptr.* = try switch (@typeInfo(T)) {
            .bool => self.registerBool(T),
            .int => self.registerInt(T),
            .float => self.registerFloat(T),
            .pointer => self.registerPointer(T),
            .array => self.registerArray(T),
            .@"struct" => self.registerStruct(T),
            .optional => self.registerOptional(T),
            .@"enum" => self.registerEnum(T),
            .@"union" => self.registerUnion(T),
            .@"fn" => @compileError("unimplemented"),
            else => @compileError("cannot register comptime-only type " ++ @typeName(T)),
        };

        // Try load custom formatter
        if (util.hasMethod(T, "customFormat")) {
            self.setFormatter(T, &@field(T, "customFormat"));
        }

        return self.registered_types.getPtr(type_id).?; // Re-obtain pointer in case any other types were recursively registered.

    }

    pub fn getTypeInfo(self: *const Self, type_name: []const u8) ?*Type {
        const maybe_type_id = self.getTypeId(type_name);
        if (maybe_type_id) |type_id| {
            return self.registered_types.getPtr(type_id);
        }
        return null;
    }

    pub fn getTypeId(self: *const Self, type_name: []const u8) ?TypeId {
        return self.type_names.get(type_name);
    }

    pub fn isTypeRegistered(self: *const Self, comptime T: type) bool {
        return self.registered_types.contains(typeId(T));
    }

    fn registerBool(self: *Self, comptime T: type) !Type {
        _ = .{ self, T };
        return Type{ .bool = {} };
    }

    fn registerInt(self: *Self, comptime T: type) !Type {
        _ = self;
        const info = @typeInfo(T).int;
        const is_pointer_sized = (T == usize or T == isize);
        return Type{ .int = .{
            .bits = info.bits,
            .signedness = info.signedness,
            .is_pointer_sized = is_pointer_sized,
        } };
    }

    fn registerFloat(self: *Self, comptime T: type) !Type {
        _ = self;
        const info = @typeInfo(T).float;
        return Type{ .float = .{
            .bits = info.bits,
        } };
    }

    fn registerPointer(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).pointer;
        const child = try self.registerType(info.child);
        const size = switch (info.size) {
            .one => Type.Pointer.Size.one,
            .many => Type.Pointer.Size.many,
            .slice => Type.Pointer.Size.slice,
            .c => Type.Pointer.Size.c,
        };
        return Type{ .pointer = .{
            .name = @typeName(T),
            .size = size,
            .is_const = info.is_const,
            .alignment = info.alignment,
            .child = child,
        } };
    }

    fn registerArray(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).array;
        const child = try self.registerType(info.child);
        return Type{ .array = .{
            .name = @typeName(T),
            .len = info.len,
            .child = child,
        } };
    }

    fn registerStruct(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).@"struct";
        const fields = try self.allocator.alloc(Type.StructField, info.fields.len);
        errdefer self.allocator.free(fields);
        inline for (info.fields, 0..) |field, i| {
            const field_type = try self.registerType(field.type);
            fields[i] = Type.StructField{
                .name = field.name,
                .type = field_type,
                .default_value_ptr = field.default_value_ptr,
                .alignment = field.alignment,
                .offset = @offsetOf(T, field.name),
            };
        }
        const decls = try self.allocator.alloc(Type.Declaration, info.decls.len);
        errdefer self.allocator.free(decls);
        inline for (info.decls, 0..) |decl, i| {
            decls[i] = Type.Declaration{ .name = decl.name };
        }
        return Type{ .@"struct" = .{
            .name = @typeName(T),
            .fields = fields,
            .decls = decls,
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
        } };
    }

    fn registerOptional(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).optional;
        const child = try self.registerType(info.child);
        return Type{ .optional = .{
            .name = @typeName(T),
            .child = child,
        } };
    }

    fn registerEnum(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).@"enum";
        const tag_type = try self.registerType(info.tag_type);
        const fields = try self.allocator.alloc(Type.EnumField, info.fields.len);
        errdefer self.allocator.free(fields);
        inline for (info.fields, 0..) |field, i| {
            fields[i] = Type.EnumField{
                .name = field.name,
                .value = field.value,
            };
        }
        const decls = try self.allocator.alloc(Type.Declaration, info.decls.len);
        errdefer self.allocator.free(decls);
        inline for (info.decls, 0..) |decl, i| {
            decls[i] = Type.Declaration{ .name = decl.name };
        }
        return Type{ .@"enum" = .{
            .name = @typeName(T),
            .tag_type = tag_type,
            .fields = fields,
            .decls = decls,
        } };
    }

    fn registerUnion(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).@"union";
        const tag_type = if (info.tag_type) |tag| try self.registerType(tag) else null;
        const fields = try self.allocator.alloc(Type.UnionField, info.fields.len);
        errdefer self.allocator.free(fields);
        inline for (info.fields, 0..) |field, i| {
            const field_type = if (field.type != void) try self.registerType(field.type) else null;
            fields[i] = Type.UnionField{
                .name = field.name,
                .type = field_type,
                .alignment = field.alignment,
            };
        }
        const decls = try self.allocator.alloc(Type.Declaration, info.decls.len);
        errdefer self.allocator.free(decls);
        inline for (info.decls, 0..) |decl, i| {
            decls[i] = Type.Declaration{ .name = decl.name };
        }
        return Type{ .@"union" = .{
            .name = @typeName(T),
            .layout = info.layout,
            .tag_type = tag_type,
            .fields = fields,
            .decls = decls,
            .size = @sizeOf(T),
        } };
    }

    fn registerFn(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).@"fn";
        std.debug.print("{}\n", .{info.is_generic});
        if (info.is_generic) return error.GenericFnUnsupported; // FIXME: switch on corrupt value panic
        if (info.is_var_args) return error.VarArgFnUnsupported;

        const return_type = self.registerType(info.return_type);
        const params = try self.allocator.alloc(*Type, info.params.len);
        errdefer self.allocator.free(params);
        inline for (info.params, 0..) |param, i| {
            if (param.is_generic) return error.GenericFnUnsupported;
            const param_type = param.type orelse return error.GenericFnUnsupported;
            params[i] = try self.registerType(param_type);
        }
        return Type{ .@"fn" = .{
            .calling_convention = info.calling_convention,
            .return_type = return_type,
            .params = params,
        } };
    }

    fn setFormatter(self: *Self, comptime T: type, formatter: CustomFormatter) void {
        const type_id = typeId(T);
        std.debug.assert(self.registered_structs.contains(type_id));
        try self.formatters.put(self.allocator, type_id, formatter);
    }
};

test "TypeRegistry register struct" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;

    var registry = TypeRegistry.init(allocator);
    defer registry.deinit();

    const TestEnum = enum { a, b, c };

    const TestUnion = union(enum) {
        float: f32,
        char: u8,
        empty,
    };

    const InnerStruct = struct {
        text: []const u8,
    };

    const TestStruct = struct {
        is_true: bool = false,
        number: i32 = 123,
        float: f16 = 9.99,
        pointer: *const f64 = &@as(f64, std.math.pi),
        array: [4]u8 = [_]u8{ 10, 9, 8, 7 },
        inner: InnerStruct = .{ .text = "test" },
        maybe: ?bool = null,
        test_enum: TestEnum = .c,
        test_union: TestUnion = .{ .char = 'x' },

        pub const my_decl = 0;
    };

    const runtime_type = try registry.registerType(TestStruct);
    try expect(runtime_type.* == .@"struct");

    const comptime_info = @typeInfo(TestStruct).@"struct";
    const runtime_info = runtime_type.@"struct";

    try expect(std.mem.eql(u8, runtime_info.name, @typeName(TestStruct)));
    try expect(runtime_info.fields.len == comptime_info.fields.len);
    try expect(runtime_info.decls.len == comptime_info.decls.len);
    try expect(runtime_info.size == @sizeOf(TestStruct));
    try expect(runtime_info.alignment == @alignOf(TestStruct));
}
