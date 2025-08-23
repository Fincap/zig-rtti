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
    type_id_generation: TypeIdGeneration = .linksections,
};

pub const TypeIdGeneration = enum {
    /// Uses linksection to assign each type a unique offset-based ID at compile time, on the
    /// assumption that section `.bss.RTTI_Types0` will appear before `.bss.RTTI_Types1` in memory,
    /// however this behaviour is *not* guaranteed by the linker and may result in non-contiguous
    /// and/or non-sequential IDs being generated.
    linksections,
    /// Type Ids will be generated from pointers into the program's `.bss` section at runtime, which
    /// will result in numbers which are clustered together but not necessarily contiguous.
    clustered,
    /// Type Ids will be generated from the 64-bit FNV-1a hash of the type name.
    hash,
};

test {
    @import("std").testing.refAllDecls(@This());
}
