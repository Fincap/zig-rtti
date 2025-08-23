const options = @import("root.zig").options;

pub const TypeId = usize;

/// Returns a unique identifier for the given type, which can be used at runtime.
///
/// Uses linksection to assign each type a unique offset-based ID at compile time, on the
/// assumption that section `.bss.RTTI_Types0` will appear before `.bss.RTTI_Types1` in memory,
/// however this behaviour is *not* guaranteed by the linker and may result in non-contiguous and/or
/// non-sequential IDs being generated.
///
/// If this behaviour is undesirable for your specific use case and you would prefer to either
/// explicitly generate non-contiguous and non-sequential IDs, or use the hash of the type's name,
/// you can configure the library in your project root:
///
/// ```
/// pub const rtti_options: rtti.Options = .{
///     .type_id_generation = .hash,  // or `.clustered`
/// };
/// ```
/// (This works the same way as `std.Options`)
pub fn getTypeId(comptime T: type) TypeId {
    switch (options.type_id_generation) {
        .linksections => {
            const H = struct {
                const byte: u8 linksection(section_name ++ "1") = 0;
                const _ = T;
            };
            return &H.byte - &@"RTTI_Types.head";
        },
        .clustered => {
            const H = struct {
                const byte: u8 = 0;
                const _ = T;
            };
            return @intFromPtr(&H.byte);
        },
        .hash => {
            return fnv1a(@typeName(T));
        },
    }
}
const section_name = ".bss.RTTI_Types";
const @"RTTI_Types.head": u8 linksection(section_name ++ "0") = 0;

inline fn fnv1a(comptime input: []const u8) usize {
    const basis: usize = 0xcbf29ce484222325;
    const prime: usize = 0x100000001b3;
    comptime var hash: usize = basis;
    inline for (input) |byte| {
        hash ^= byte;
        hash *%= prime;
    }
    return hash;
}
