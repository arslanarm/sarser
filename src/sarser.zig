const std = @import("std");

pub fn Deserializer(comptime T: type) type {
    return struct { deserialize: fn (std.mem.Allocator, []const u8) SarserError!T };
}

pub const SarserError = error{ DeserializerNotFound, CannotDeserialize, NotEnoughArguments, OutOfMemory, CannotReadArgument, TooManyArguments };

pub const Sarser = struct {
    deserializers: std.StringHashMap(Deserializer(void)),
    allocator: std.mem.Allocator,

    // Inits the parser with the StringHashMap that will be used to store
    // deserializer for specific type. Deserializer for standard primitives can be overwritten
    pub fn init(allocator: std.mem.Allocator) !Sarser {
        var parser = Sarser{
            .deserializers = std.StringHashMap(Deserializer(void)).init(allocator),
            .allocator = allocator,
        };
        try addDefaultDeserializers(&parser);
        return parser;
    }

    pub fn deinit(self: *Sarser) void {
        self.deserializers.deinit();
    }

    // Adds a deserializer into the hashmap
    pub fn addCustomDeserializer(self: *Sarser, comptime T: type, deserializer: *const Deserializer(T)) !void {
        try self.deserializers.put(@typeName(T), @ptrCast(*const Deserializer(void), deserializer).*);
    }

    // Gets a deserializer for a specific type or null if it doesn't exist
    pub fn getDeserializer(self: Sarser, comptime T: type) ?Deserializer(T) {
        return switch (@typeInfo(T)) {
            .Int => IntDeserializer(T).init().deserializer,
            .Float => FloatDeserializer(T).init().deserializer,
            else => @ptrCast(*?Deserializer(T), &self.deserializers.get(@typeName(T))).*,
        };
    }

    // Parses the std.process.args() with the struct, union
    pub fn parse(self: Sarser, comptime T: type) SarserError!T {
        var argsIter = std.process.args();
        _ = argsIter.skip();

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        defer deinitArrayList(self.allocator, args);

        var next = argsIter.next(self.allocator);
        while (next != null) : (next = argsIter.next(self.allocator)) {
            const arg = (next.?) catch {
                return SarserError.CannotReadArgument;
            };
            if (arg.len != 0) {
                args.append(arg) catch {
                    return SarserError.CannotReadArgument;
                };
            } else {
                self.allocator.free(arg);
            }
        }

        const result = switch (@typeInfo(T)) {
            .Struct => try self.parseFields(T, &args),
            .Union => label: {
                const t = try self.parseUnion(T, args.items[0]);
                self.allocator.free(args.orderedRemove(0));
                break :label t;
            },
            else => {
                @compileError("Sarser: type " ++ @typeName(T) ++ " is not supported");
            },
        };

        if (args.items.len != 0) {
            return SarserError.TooManyArguments;
        }

        return result;
    }

    fn parseFields(self: Sarser, comptime T: type, args: *std.ArrayList([]const u8)) SarserError!T {
        var result: T = undefined;
        const fields = std.meta.fields(T);
        inline for (fields) |field| {
            const deserializer = self.getDeserializer(field.field_type);
            if (deserializer != null) {
                for (args.items) |arg, index| {
                    if (!std.mem.startsWith(u8, arg, "--" ++ field.name ++ "=")) {
                        @field(&result, field.name) = try deserializer.?.deserialize(self.allocator, arg);
                        self.allocator.free(args.orderedRemove(index));
                        break;
                    }
                } else {
                    return SarserError.NotEnoughArguments;
                }
            } else {
                var found = false;
                switch (@typeInfo(field.field_type)) {
                    .Optional => |opt| {
                        @field(&result, field.name) = try self.parseOptional(opt, field.name, args);
                        found = true;
                    },
                    .Union => {
                        for (args.items) |arg, index| {
                            if (!std.mem.startsWith(u8, arg, "--" ++ field.name ++ "=")) {
                                @field(&result, field.name) = try self.parseUnion(field.field_type, arg);
                                found = true;
                                self.allocator.free(args.orderedRemove(index));
                                break;
                            }
                        } else {
                            return SarserError.NotEnoughArguments;
                        }
                    },
                    else => {},
                }
                if (!found) {
                    return SarserError.DeserializerNotFound;
                }
            }
        }
        return result;
    }

    fn parseOptional(self: Sarser, comptime T: std.builtin.TypeInfo.Optional, comptime name: []const u8, args: *std.ArrayList([]const u8)) SarserError!?T.child {
        const optionalDeserializer = self.getDeserializer(T.child);
        if (optionalDeserializer != null) {
            for (args.items) |arg, index| {
                if (std.mem.startsWith(u8, arg, "--" ++ name ++ "=")) {
                    const value = try optionalDeserializer.?.deserialize(self.allocator, arg[(comptime ("--" ++ name ++ "=").len)..]);
                    self.allocator.free(args.orderedRemove(index));
                    return value;
                }
            } else {
                return null;
            }
        } else {
            switch (@typeInfo(T.child)) {
                .Union => {
                    for (args.items) |arg, index| {
                        if (std.mem.startsWith(u8, arg, "--" ++ name ++ "=")) {
                            const value = try self.parseUnion(T.child, arg[("--" ++ name ++ "=").len..]);
                            self.allocator.free(args.orderedRemove(index));
                            return value;
                        }
                    } else {
                        return null;
                    }
                },
                else => {
                    return SarserError.DeserializerNotFound;
                },
            }
        }
    }

    fn parseUnion(self: Sarser, comptime T: type, str: []const u8) SarserError!T {
        switch (@typeInfo(T)) {
            .Union => |un| {
                inline for (un.fields) |field| {
                    const deserializer = self.getDeserializer(field.field_type) orelse {
                        return SarserError.DeserializerNotFound;
                    };

                    const value = deserializer.deserialize(self.allocator, str) catch |err|
                        switch (err) {
                        SarserError.CannotDeserialize => null,
                        else => {
                            return err;
                        },
                    };
                    if (value != null) {
                        return @unionInit(T, field.name, value.?);
                    }
                }
                return SarserError.CannotDeserialize;
            },
            else => {
                unreachable();
            },
        }
    }
};

fn addDefaultDeserializers(parser: *Sarser) !void {
    try parser.addCustomDeserializer([]const u8, &StringDeserializer);
    try parser.addCustomDeserializer(bool, &BooleanDeserializer);
}

fn IntDeserializer(comptime T: type) type {
    return struct {
        deserializer: Deserializer(T),
        fn init() IntDeserializer(T) {
            return IntDeserializer(T){
                .deserializer = Deserializer(T){ .deserialize = parseInt },
            };
        }
        fn parseInt(_: std.mem.Allocator, s: []const u8) SarserError!T {
            return std.fmt.parseInt(T, s, 10) catch SarserError.CannotDeserialize;
        }
    };
}

const StringDeserializer = Deserializer([]const u8){ .deserialize = parseString };
fn parseString(allocator: std.mem.Allocator, str: []const u8) SarserError![]const u8 {
    var newStr = allocator.alloc(u8, str.len) catch {
        return SarserError.OutOfMemory;
    };
    std.mem.copy(u8, newStr, str);
    return newStr;
}

fn FloatDeserializer(comptime T: type) type {
    return struct {
        deserializer: Deserializer(T),
        fn init() FloatDeserializer(T) {
            return FloatDeserializer(T){ .deserializer = Deserializer(T){ .deserialize = parseFloat } };
        }
        fn parseFloat(_: std.mem.Allocator, str: []const u8) SarserError!T {
            return std.fmt.parseFloat(T, str) catch SarserError.CannotDeserialize;
        }
    };
}

const BooleanDeserializer = Deserializer(bool){ .deserialize = parseBoolean };
fn parseBoolean(_: std.mem.Allocator, str: []const u8) SarserError!bool {
    return if (std.mem.eql(u8, str, "true")) true else if (std.mem.eql(u8, str, "false")) false else SarserError.CannotDeserialize;
}

fn deinitArrayList(allocator: std.mem.Allocator, args: std.ArrayList([]const u8)) void {
    for (args.items) |item| {
        std.log.info("Deinit {s}", .{item});
        allocator.free(item);
    }
}

test "check union" {
    const allocator = std.testing.allocator;
    var parser = try Sarser.init(allocator);
    defer parser.deinit();

    const integer = try parser.parseUnion(union { integer: i32, float: f64 }, "123");
    const float = try parser.parseUnion(union { integer: i32, float: f64 }, "123.0");
    try std.testing.expect(integer.integer == 123);
    try std.testing.expect(float.float == 123.0);
}

test "check struct" {
    const allocator = std.testing.allocator;
    var parser = try Sarser.init(allocator);
    defer parser.deinit();
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    try args.append(try allocator.dupe(u8, "123"));
    try args.append(try allocator.dupe(u8, "yes"));
    try args.append(try allocator.dupe(u8, "--c=true"));

    const value = try parser.parseFields(struct { a: i32, b: []const u8, c: ?bool }, &args);
    try std.testing.expect(value.a == 123);
    try std.testing.expect(std.mem.eql(u8, value.b, "yes"));
    try std.testing.expect(value.c.?);
    allocator.free(value.b);
}
