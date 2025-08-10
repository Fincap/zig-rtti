# zig-rtti
Runtime Type Information for Zig.

This library provides a `TypeRegistry` container for storing runtime information about types that 
are registered at comptime.

Adds in `Type`, which adapts `std.builtin.Type` to work with the subset of Zig types that are able
to be meaningfully represented at runtime:
- bool
- Int
- Float
- Pointer (single-item, many-item, slices, C)
- Array
- Struct
- Optional
- Enum
- Union

When a type refers to another type (for example, a pointer’s target, a struct’s field type, or an
optional’s payload), its `Type` holds a pointer to the corresponding `Type` instance. This works 
because the `TypeRegistry` stores all `Type` instances at [stable addresses](src/stable_map.zig), 
and the registered types are assumed to remain valid for the lifetime of the registry.

The library also includes a [formatter module](src/fmt.zig) that can inspect an opaque pointer and 
write a human-readable representation to any `std.io.AnyWriter`, and is an example of how runtime 
type information can be utilized.

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
Minimal:

```zig
const std = @import("std");
const rtti = @import("rtti");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    // `TypeRegistry` holds all registerted type metadata.
    var type_registry = rtti.TypeRegistry.init(allocator);
    defer type_registry.deinit();

    // Define and register a new type so it can be inspected at runtime.
    const MyStruct = struct {
        number: i32,
        text: []const u8,
    };
    const info = try type_registry.registerType(MyStruct);

    // Create a type-erased pointer to an instance of `MyStruct`.
    const erased: *const anyopaque = &MyStruct{ .number = 14, .text = "hello" };

    // Use the built-in formatter to print the type-erased struct’s fields at runtime.
    const writer = std.io.getStdOut().writer().any();
    try rtti.fmt.formatType(info, erased, writer);
    // Output: { number: 14, text: "hello" }
}
```

Type-erased object:

```zig
const rtti = @import("rtti");

const TypeErasedObject = struct {
    ptr: *anyopaque,
    info: *rtti.Type,
};
```
