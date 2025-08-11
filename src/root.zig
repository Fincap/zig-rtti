pub const Type = @import("type_info.zig").Type;
pub const TypeRegistry = @import("TypeRegistry.zig");

const type_id = @import("type_id.zig");
pub const getTypeId = type_id.getTypeId;
pub const TypeId = type_id.TypeId;

pub const fmt = @import("fmt.zig");
pub const util = @import("util.zig");

const root = @import("root");

/// Library-wide options that can be overridden by the root file.
pub const options: Options = if (@hasDecl(root, "rtti_options")) root.rtti_options else .{};

pub const Options = struct {
    /// Enables type ID generation via incrementing values in custom linker sections. If disabled,
    /// then type IDs will be non-contiguous and non-sequential.
    enable_linksection_typeid: bool = true,
};

test {
    @import("std").testing.refAllDecls(@This());
}
