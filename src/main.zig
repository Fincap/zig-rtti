const std = @import("std");

const rtti = @import("rtti");

const TestEnum = enum(u8) { a, b, c };

const TestUnion = union {
    float: f32,
    char: u8,
    empty: void,
};

const InnerStruct = struct {
    text: []const u8,
};

const TestStruct = struct {
    is_true: bool = false,
    number: i32 = 123,
    float: f16 = 9.99,
    pointer: *const f64 = &@as(f64, std.math.pi),
    array: [4]u32 = [_]u32{ 10, 9, 8, 7 },
    inner: InnerStruct = .{ .text = "test" },
    maybe: ?bool = null,
    test_enum: TestEnum = .c,
    test_union: TestUnion = .{ .char = 'x' },

    pub const my_decl = 0;
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var registry = rtti.TypeRegistry.init(allocator);
    defer registry.deinit();

    const test_struct = TestStruct{};
    const info = try registry.registerType(TestStruct);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try rtti.fmt.formatType(info, &test_struct, stdout);
    try stdout.flush();
}
