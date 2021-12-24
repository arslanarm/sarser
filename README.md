# SARSER - Simple ARgument parSER

Sarser is a library, purpose of which is to create a small cli programms with extremly simple api.
Some functions of other argument parser libraries are not implemented purposefully. If you want a flexable library for parsing arguments
consider using [zig-args](https://github.com/MasterQ32/zig-args).


## Usage

```
const std = @import("std");
const sarser = @import("sarser");

const allocator = std.heap.page_allocator;

pub fn main() anyerror!void {
    var parser = try sarser.Sarser.init(allocator);
    defer parser.deinit();

    const value = try parser.parse(struct {
        a: i32,
        b: ?f64,
        c: []const u8,
        d: bool
    });
    std.log.info("{}", .{value});
    
    allocator.free(value.c);
}

// ./example 123 --b=123.123 "one two three" true
// ./example 123 --b=123.123 onetwothree true
```

+ Non-optional values are consider as required arguments.
+ Optional values are consider as optional arguments.
+ Union types are allowed too. If you pass union type to `parse`, parser will assume that programm expects only one argument.
+ String arguments are allocated with the allocator and it is not parser's responsability to free strings of the value that is returned.
+ You can add your own deserializers for types(overriding default deserializers is possible with corner cases of `i'n'`, `u'n'`, `f'n'`)

```
const MyType = struct {
    hours: u8,
    minutes: u8,
};

const MyTypeDeserializer = Deserializer {
    .deserialize = parseMyType
};
fn parseMyType(_: std.mem.Allocator, str: []const u8) sarser.SarserError!MyType {
    var iter = std.mem.split(u8, str, ":");
    const hoursStr = iter.next() orelse { return sarser.SarserError.CannotDeserialize; };
    const minutesStr = iter.next() orelse { return sarser.SarserError.CannotDeserialize; };
    return MyType {
        .hours = std.fmt.parseInt(u8, hoursStr, 10) catch { return sarser.SarserError.CannotDeserialize; },
        .minutes = std.fmt.parseInt(u8, minutesStr, 10) catch { return sarser.SarserError.CannotDeserialize; },
    };
}
}

try parser.addCustomDeserializer(MyType, &MyTypeDeserializer);
const value = try parser.parse(struct {
    start: MyType,
    end: MyType
});
std.log.info("{}", .{value});
```

## Installing

Library provides `addTo(step)` function for adding the package into your project. Follow the instruction to install the library

```
---------- bash ---------------

git clone https://github.com/arslanarm/sarser/

---------- build.zig ----------

const sarser = @import("<lib-path>/build.zig");

const exe = b.addExecutable();
sarser.addTo(exe);

```

## Upcoming

+ Currently, by default only `i32` and `f64` are supported. Adding support for any number type is necessary