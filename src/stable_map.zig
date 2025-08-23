const std = @import("std");
const Allocator = std.mem.Allocator;

// TODO: move this into its own library, as it's not directly related to the RTTI library.

pub const Config = struct {
    /// Size of a chunk in bytes (entries may not use up 100% of the allocated chunk due if value
    /// size is not evenly divisible by chunk size).
    chunk_size: usize = std.heap.pageSize(),
};

/// HashMap that stores values in chunks. Keys map to an index, which is used to lookup the value
/// within one of the chunks.
///
/// Primary benefit is that pointers to value entries are guaranteed to be stable as the map grows.
///
/// Has increased overhead when accessing values via their keys, as the value needs to be accessed
/// through a double dereference. Iterating through values will be a potential cache miss on chunk
/// boundaries.
///
/// Values cannot be removed from the map as any ordered or swap remove operation would violate
/// pointer stability.
///
/// The backing storage is similar to `std.SegmentedList`, however the "shelves" in the StableMap
/// are of fixed sized rather than growing in size by powers-of-two as the SegmentedList does.
///
/// TODO: create variants for [Auto/String]StableMap, mirroring std HashMap types.
/// TODO: add more functions to access methods of underlying dictionary
pub fn StableMap(comptime K: type, comptime V: type, comptime config: Config) type {
    return struct {
        const Self = @This();

        chunks: std.ArrayList(Chunk) = .empty,
        keys: std.AutoHashMapUnmanaged(K, ValueIndex) = .empty,

        pub const entries_per_chunk = config.chunk_size / @sizeOf(V);

        pub const empty = Self{};

        /// Index of a chunk in the `chunks` list.
        const ChunkIndex = usize;
        /// "Overall" index of a value across all chunks.
        const ValueIndex = usize;

        pub const Chunk = struct {
            buffer: *[entries_per_chunk]V,
            len: usize,
        };

        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const Iterator = struct {
            map: *const Self,
            inner: std.AutoHashMapUnmanaged(K, ValueIndex).Iterator,

            pub fn next(it: *Iterator) ?Entry {
                if (it.inner.next()) |entry| {
                    return Entry{
                        .key_ptr = entry.key_ptr,
                        .value_ptr = it.map.getEntryFromIndex(entry.value_ptr.*),
                    };
                }
                return null;
            }
        };

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (self.chunks.items) |chunk| {
                allocator.free(chunk.buffer);
            }
            self.chunks.deinit(allocator);
            self.keys.deinit(allocator);
        }

        pub fn put(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            const result = try self.getOrPut(allocator, key);
            result.value_ptr.* = value;
        }

        pub fn getPtr(self: Self, key: K) ?*V {
            if (self.getIndex(key)) |index| {
                return self.getEntryFromIndex(index);
            }
            return null;
        }

        pub fn get(self: Self, key: K) ?V {
            if (self.getIndex(key)) |index| {
                return self.getEntryFromIndex(index).*;
            }
            return null;
        }

        pub fn getOrPut(self: *Self, allocator: Allocator, key: K) Allocator.Error!GetOrPutResult {
            if (self.getPtr(key)) |value_ptr| {
                return GetOrPutResult{
                    .found_existing = true,
                    .key_ptr = self.keys.getKeyPtr(key).?,
                    .value_ptr = value_ptr,
                };
            }
            const next_chunk = self.nextChunk();
            if (self.chunks.items.len <= next_chunk) {
                try self.chunks.append(allocator, Chunk{
                    .buffer = try allocator.create([entries_per_chunk]V),
                    .len = 0,
                });
            }
            const chunk = &self.chunks.items[next_chunk];
            const entry_offset = chunk.len;
            const index = next_chunk * entries_per_chunk + entry_offset;
            chunk.len += 1;
            try self.keys.put(allocator, key, index);
            return GetOrPutResult{
                .found_existing = false,
                .key_ptr = self.keys.getKeyPtr(key).?,
                .value_ptr = &chunk.buffer[entry_offset],
            };
        }

        pub fn contains(self: Self, key: K) bool {
            return self.keys.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.keys.count();
        }

        pub fn iterator(self: *const Self) Iterator {
            return .{ .map = self, .inner = self.keys.iterator() };
        }

        /// Returns the index of the chunk where the next entry will be inserted into. The index is
        /// not guaranteed to point to an allocated chunk.
        fn nextChunk(self: Self) ChunkIndex {
            if (self.chunks.items.len == 0) return 0;
            var last_index = self.chunks.items.len - 1;
            const last_chunk = self.chunks.items[last_index];
            if (last_chunk.len >= entries_per_chunk) last_index += 1;
            return last_index;
        }

        /// Returns the index of the given key.
        fn getIndex(self: Self, key: K) ?ValueIndex {
            return self.keys.get(key);
        }

        /// Returns a pointer to the chunk entry located at the given index.
        fn getEntryFromIndex(self: Self, index: ValueIndex) *V {
            const chunk_index = chunkFromIndex(index);
            const entry_offset = getOffsetInChunk(chunk_index, index);
            return &self.chunks.items[chunk_index].buffer[entry_offset];
        }

        /// Returns the index of the chunk which contains the given value index.
        inline fn chunkFromIndex(index: ValueIndex) ChunkIndex {
            return index / entries_per_chunk;
        }

        /// Given an index of a chunk, and an index, returns the element index of the value within
        /// the chunk.
        inline fn getOffsetInChunk(chunk: usize, index: ValueIndex) usize {
            return index - (chunk * entries_per_chunk);
        }
    };
}
