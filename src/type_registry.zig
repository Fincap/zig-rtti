const std = @import("std");
const Allocator = std.mem.Allocator;

const CustomFormatter = @import("fmt.zig").CustomFormatter;
const StableMap = @import("stable_map.zig").StableMap;
const type_info = @import("type_info.zig");
const Type = type_info.Type;
const Struct = type_info.Struct;
const TypeId = type_info.TypeId;
const EnumField = type_info.EnumField;
const Declaration = type_info.Declaration;
const typeId = type_info.typeId;

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

        // Map type name -> type ID (*feels* like this needs to be done before the type's child types
        // are registered, but I need to check myself on that assumption)
        const type_name = @typeName(T);
        try self.type_names.put(self.allocator, type_name, type_id);
        errdefer _ = self.type_names.remove(type_name);

        entry.value_ptr.* = try switch (@typeInfo(T)) {
            .bool => self.registerBool(T),
            .int => self.registerInt(T),
            .pointer => self.registerPointer(T),
            .float => self.registerFloat(T),
            .array => self.registerArray(T),
            .@"struct" => self.registerStruct(T),
            .optional => self.registerOptional(T),
            .@"enum" => self.registerEnum(T),
            .@"union",
            .@"fn",
            => @compileError("register type for " ++ @typeName(T) ++ " unimplemented"),
            else => @compileError("cannot register comptime-only type"),
        };

        // Try load custom formatter
        if (type_info.hasMethod(T, "customFormat")) {
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
            .one => type_info.Pointer.Size.one,
            .many => type_info.Pointer.Size.many,
            .slice => type_info.Pointer.Size.slice,
            .c => type_info.Pointer.Size.c,
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
        // Recursively register struct's fields that are also structs
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and !self.isTypeRegistered(field.type)) {
                _ = try self.registerType(field.type);
            }
        }

        return Type{ .@"struct" = try Struct.init(T, self) };
    }

    fn registerOptional(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).optional;
        const child = try self.registerType(info.child);
        return Type{ .optional = .{ .child = child } };
    }

    fn registerEnum(self: *Self, comptime T: type) !Type {
        const info = @typeInfo(T).@"enum";
        const tag_type = try self.registerType(info.tag_type);
        const fields = try self.allocator.alloc(EnumField, info.fields.len);
        inline for (info.fields, 0..) |field, i| {
            fields[i] = EnumField{
                .name = field.name,
                .value = field.value,
            };
        }
        const decls = try self.allocator.alloc(Declaration, info.decls.len);
        inline for (info.decls, 0..) |decl, i| {
            decls[i] = Declaration{ .name = decl.name };
        }
        return Type{ .@"enum" = .{
            .name = @typeName(T),
            .tag_type = tag_type,
            .fields = fields,
            .decls = decls,
        } };
    }

    fn setFormatter(self: *Self, comptime T: type, formatter: CustomFormatter) void {
        const type_id = typeId(T);
        std.debug.assert(self.registered_structs.contains(type_id));
        try self.formatters.put(self.allocator, type_id, formatter);
    }
};
