# zig-rtti
Runtime Type Information for Zig.

Exposes the `TypeRegistry` container which can be used to store runtime information about a type
that has been registered at comptime.

## Installation
Add zig-rtti as a dependency by running the following command in your project root:

```
zig fetch --save git+https://github.com/Fincap/zig-rtti
```

Then updating your `build.zig` to include the following:

```zig
const rtti_dep = b.dependency("rtti", .{ 
    .target = target,
    .optimize = optimize
});
const rtti = rtti_dep.module("rtti");
exe.root_module.addImport("rtti", rtti);
```

## Example
```zig
const std = @import("std");
const rtti = @import("rtti");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    // `TypeRegistry` is the backing storage of type information.
    var type_registry = rtti.TypeRegistry.init(allocator);
    defer type_registry.deinit();

    // Define and register a new type so it can be inspected at runtime.
    const MyStruct = struct {
        number: i32,
        text: []const u8,
    };
    const info = try type_registry.registerType(MyStruct);

    // Create a type-erased pointer to a new instance of our struct.
    const erased: *const anyopaque = &MyStruct{ .number = 14, .text = "hello" };

    // Use the library's default formatting utility functions to print out the type-erased struct's
    // values at runtime.
    const writer = std.io.getStdOut().writer().any();
    try rtti.fmt.formatType(info, erased, writer);
    // Output: { number: 14, text: "hello" }
}
```