const std = @import("std");
const Allocator = std.mem.Allocator;

const CustomFormatter = @import("fmt.zig").CustomFormatter;
const type_info = @import("type_info.zig");
const Type = type_info.Type;
const Struct = type_info.Struct;
const TypeId = type_info.TypeId;
const typeId = type_info.typeId;

/// Registry of runtime information for types.
pub const TypeRegistry = struct {
    const Self = @This();

    allocator: Allocator,
    registered_types: std.AutoHashMapUnmanaged(TypeId, Type) = .empty,
    type_names: std.StringArrayHashMapUnmanaged(TypeId) = .empty,
    formatters: std.AutoHashMapUnmanaged(TypeId, CustomFormatter) = .empty,

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

        entry.value_ptr.* = try switch (@typeInfo(T)) {
            .@"struct" => self.registerStruct(T),
            .bool,
            .int,
            .float,
            .pointer,
            .array,
            .optional,
            .@"enum",
            .@"union",
            .@"fn",
            => @compileError("unimplemented"),
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

    fn registerStruct(self: *Self, comptime T: type) !Type {
        const @"struct" = try Struct.init(T, self.allocator);

        // Recursively register struct's fields that are also structs
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and !self.isTypeRegistered(field.type)) {
                _ = try self.registerType(field.type);
            }
        }
        return Type{ .@"struct" = @"struct" };
    }

    fn setFormatter(self: *Self, comptime T: type, formatter: CustomFormatter) void {
        const type_id = typeId(T);
        std.debug.assert(self.registered_structs.contains(type_id));
        try self.formatters.put(self.allocator, type_id, formatter);
    }
};
