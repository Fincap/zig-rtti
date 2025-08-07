const std = @import("std");
const Allocator = std.mem.Allocator;

const CustomFormatter = @import("fmt.zig").CustomFormatter;
const type_info = @import("type_info.zig");
const Struct = type_info.Struct;
const TypeId = type_info.TypeId;
const typeId = type_info.typeId;

/// Registry of runtime information for types.
pub const TypeRegistry = struct {
    const Self = @This();

    allocator: Allocator,
    registered_types: std.AutoHashMapUnmanaged(TypeId, Struct) = .empty, // TODO: store `Type` rather than `Struct`
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

    /// Results in heap allocations. Pointers in returned struct are owned by the registry, and are
    /// expected to live for the remainder of the program's lifetime.
    pub fn registerType(self: *Self, comptime T: type) !*Struct {
        const type_id = typeId(T);
        const entry = try self.registered_types.getOrPut(self.allocator, type_id);
        if (entry.found_existing) {
            return entry.value_ptr;
        }
        entry.value_ptr.* = try Struct.init(T, self.allocator);

        // Map type name -> type ID
        const type_name = @typeName(T);
        const name_entry = try self.type_names.getOrPut(self.allocator, type_name);
        name_entry.value_ptr.* = type_id;

        // Try load custom formatter
        if (type_info.hasMethod(T, "customFormat")) {
            setFormatter(T, &@field(T, "customFormat"));
        }

        // Recursively register struct's fields that are also structs
        // NOTE: if this runs, then the `entry.value_ptr` will be invalidated.
        var child_type_registered = false;
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and !isTypeRegistered(field.type)) {
                _ = registerType(field.type);
                child_type_registered = true;
            }
        }

        if (child_type_registered) {
            return self.registered_types.getPtr(type_id).?;
        } else {
            return entry.value_ptr; // pointer still valid
        }
    }

    pub fn getTypeInfo(self: *const Self, type_name: []const u8) ?*Struct {
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

    fn setFormatter(comptime T: type, allocator: Allocator, formatter: CustomFormatter) void {
        const type_id = typeId(T);
        std.debug.assert(Self.registered_types.contains(type_id));
        try Self.formatters.put(allocator, type_id, formatter);
    }
};
