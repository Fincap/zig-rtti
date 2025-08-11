pub const TypeId = usize;

/// Returns a unique identifier for the given type, which can be used at runtime.
///
/// Uses linksection to assign each type a unique offset-based ID at compile time, on the
/// assumption that section `.bss.RTTI_Types0` will appear before `.bss.RTTI_Types1` in memory,
/// however this behaviour is *not* guaranteed by the linker and may result in sparse IDs being
/// generated.
pub fn getTypeId(comptime T: type) TypeId {
    const H = struct {
        const byte: u8 linksection(section_name ++ "1") = 0;
        const _ = T;
    };
    return &H.byte - &@"RTTI_Types.head";
}
const section_name = ".bss.RTTI_Types";
const @"RTTI_Types.head": u8 linksection(section_name ++ "0") = 0;
