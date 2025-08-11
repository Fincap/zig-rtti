const options = @import("root.zig").options;

pub const TypeId = usize;

/// Returns a unique identifier for the given type, which can be used at runtime.
///
/// Uses linksection to assign each type a unique offset-based ID at compile time, on the
/// assumption that section `.bss.RTTI_Types0` will appear before `.bss.RTTI_Types1` in memory,
/// however this behaviour is *not* guaranteed by the linker and may result in non-contiguous and/or
/// non-sequential IDs being generated.
///
/// If this behaviour is undesirable for your specific toolchain/target and you would prefer to
/// explicitly generate non-contiguous and non-sequential IDs, you can configure the library in your
/// project root:
///
/// ```
/// pub const rtti_options: rtti.Options = .{
///     .enable_linksection_typeid = false,
/// };
/// ```
/// (This works the same way as `std.Options`)
pub fn getTypeId(comptime T: type) TypeId {
    if (options.enable_linksection_typeid) {
        const H = struct {
            const byte: u8 linksection(section_name ++ "1") = 0;
            const _ = T;
        };
        return &H.byte - &@"RTTI_Types.head";
    } else {
        const H = struct {
            const byte: u8 = 0;
            const _ = T;
        };
        return @intFromPtr(&H.byte);
    }
}
const section_name = ".bss.RTTI_Types";
const @"RTTI_Types.head": u8 linksection(section_name ++ "0") = 0;
