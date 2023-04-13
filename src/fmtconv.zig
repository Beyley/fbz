const std = @import("std");
const img = @import("zigimg/zigimg.zig");

const Image = img.Image;

/// Converts a 24-bit RGB color to a 16-bit color, for use in the framebuffer.
// fn make16Color(r: u8, g: u8, b: u8) u16 {
//     return (((@as(u16, r >> 3) & 31) << 11) |
//         ((@as(u16, g >> 2) & 63) << 5) |
//         (@as(u16, b >> 3) & 31));
// }

/// Gets the amount of bits to shift right to turn said integer into the destination type.
fn getShiftAmount(comptime SourceType: type, comptime DestType: type) struct { amount: comptime_int, direction: enum { Left, NoDirection, Right } } {
    const dest_bits = switch (@typeInfo(DestType)) {
        .Int => @typeInfo(DestType).Int.bits,
        else => @compileError("Destination type must be an integer"),
    };

    const src_bits = switch (@typeInfo(SourceType)) {
        .Int => @typeInfo(SourceType).Int.bits,
        else => @compileError("Source type must be an integer"),
    };

    if (dest_bits > src_bits) {
        //if the destination is larger, then we need to shift left to make it bigger
        return .{ .amount = dest_bits - src_bits, .direction = .Left };
    } else if (dest_bits < src_bits) {
        //if the destination is smaller, then we need to shift right to make it smaller
        return .{ .amount = src_bits - dest_bits, .direction = .Right };
    } else {
        return .{ .amount = 0, .direction = .NoDirection };
    }
}

pub fn shiftLeftShiftingInLSB(comptime Type: type, x: anytype, comptime n: comptime_int) Type {
    const mask = @as(Type, (1 << n) - 1);
    return @intCast(Type, (@as(Type, x) << n) | ((x & 1) * mask));
}

fn make16Color(comptime RedType: type, comptime BlueType: type, comptime GreenType: type, r: anytype, g: anytype, b: anytype) u16 {
    @setFloatMode(std.builtin.FloatMode.Optimized);

    var destRed: u5 = 0;
    var destGreen: u6 = 0;
    var destBlue: u5 = 0;

    switch (@typeInfo(RedType)) {
        .Int => |int| {
            if (int.signedness == .signed)
                @compileError("Converting from a signed integer is not supported!");

            const shift = getShiftAmount(RedType, u5);

            const dest: type = u5;

            //Positive means shift right, negative means shift left
            if (shift.direction == .Right) {
                destRed = @intCast(dest, r >> shift.amount);
            } else if (shift.direction == .Left) {
                // destRed = @intCast(dest, r << shift.amount);
                destRed = @intCast(dest, shiftLeftShiftingInLSB(dest, r, shift.amount));
            } else {
                destRed = @as(dest, r);
            }
        },
        .Float => {
            const dest: type = u5;

            const max = @as(RedType, std.math.maxInt(dest));

            destRed = @floatToInt(dest, r * max);
        },
        else => @compileError("Converting from that format is not supported!"),
    }

    switch (@typeInfo(GreenType)) {
        .Int => |int| {
            if (int.signedness == .signed)
                @compileError("Converting from a signed integer is not supported!");

            const shift = getShiftAmount(GreenType, u6);

            const dest: type = u6;

            //Positive means shift right, negative means shift left
            if (shift.direction == .Right) {
                destGreen = @intCast(dest, g >> shift.amount);
            } else if (shift.direction == .Left) {
                // destGreen = @intCast(dest, g << shift.amount);
                destGreen = @intCast(dest, shiftLeftShiftingInLSB(dest, g, shift.amount));
            } else {
                destGreen = @as(dest, g);
            }
        },
        .Float => {
            const dest: type = u6;

            const max = @as(GreenType, std.math.maxInt(dest));

            destGreen = @floatToInt(dest, g * max);
        },
        else => @compileError("Converting from that format is not supported!"),
    }

    switch (@typeInfo(BlueType)) {
        .Int => |int| {
            if (int.signedness == .signed)
                @compileError("Converting from a signed integer is not supported!");

            const shift = getShiftAmount(BlueType, u5);

            const dest: type = u5;

            //Positive means shift right, negative means shift left
            if (shift.direction == .Right) {
                destBlue = @intCast(dest, b >> shift.amount);
            } else if (shift.direction == .Left) {
                // destBlue = @intCast(dest, b << shift.amount);
                destBlue = @intCast(dest, shiftLeftShiftingInLSB(dest, b, shift.amount));
            } else {
                destBlue = @as(dest, b);
            }
        },
        .Float => {
            const dest: type = u5;

            const max = @as(BlueType, std.math.maxInt(dest));

            destBlue = @floatToInt(dest, b * max);
        },
        else => @compileError("Converting from that format is not supported!"),
    }

    return (((@as(u16, destRed)) << 11) |
        ((@as(u16, destGreen)) << 5) |
        (@as(u16, destBlue)));
}

pub fn convertToRGB565(allocator: std.mem.Allocator, image: *img.Image) ![]u16 {
    return switch (image.pixelFormat()) {
        .invalid => @panic("Invalid format passed into convertToRGB565"),
        .indexed1 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []u1 = image.pixels.indexed1.indices;
            for (pixels, 0..) |*pixel, i| {
                const col = image.pixels.indexed1.palette[old_pixels[i]];
                pixel.* = make16Color(u8, u8, u8, col.r, col.g, col.b);
            }

            return pixels;
        },
        .indexed2 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []u2 = image.pixels.indexed2.indices;
            for (pixels, 0..) |*pixel, i| {
                const col = image.pixels.indexed2.palette[old_pixels[i]];
                pixel.* = make16Color(u8, u8, u8, col.r, col.g, col.b);
            }

            return pixels;
        },
        .indexed4 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []u4 = image.pixels.indexed4.indices;
            for (pixels, 0..) |*pixel, i| {
                const col = image.pixels.indexed4.palette[old_pixels[i]];
                pixel.* = make16Color(u8, u8, u8, col.r, col.g, col.b);
            }

            return pixels;
        },
        .indexed8 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []u8 = image.pixels.indexed8.indices;
            for (pixels, 0..) |*pixel, i| {
                const col = image.pixels.indexed8.palette[old_pixels[i]];
                pixel.* = make16Color(u8, u8, u8, col.r, col.g, col.b);
            }

            return pixels;
        },
        .indexed16 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []u16 = image.pixels.indexed16.indices;
            for (pixels, 0..) |*pixel, i| {
                const col = image.pixels.indexed16.palette[old_pixels[i]];
                pixel.* = make16Color(u8, u8, u8, col.r, col.g, col.b);
            }

            return pixels;
        },
        .grayscale1 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale1 = image.pixels.grayscale1;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u1, u1, u1, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale2 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale2 = image.pixels.grayscale2;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u2, u2, u2, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale4 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale4 = image.pixels.grayscale4;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u4, u4, u4, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale8 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale8 = image.pixels.grayscale8;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale16 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale16 = image.pixels.grayscale16;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u16, u16, u16, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale8Alpha => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale8Alpha = image.pixels.grayscale8Alpha;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        .grayscale16Alpha => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Grayscale16Alpha = image.pixels.grayscale16Alpha;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u16, u16, u16, old_pixels[i].value, old_pixels[i].value, old_pixels[i].value);
            }

            return pixels;
        },
        //basically just cast the data from rgb565 to u16, same format
        .rgb565 => @ptrCast([*]u16, image.pixels.rgb565.ptr)[0..image.pixels.rgb565.len],
        .rgb555 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgb555 = image.pixels.rgb555;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u5, u5, u5, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .rgb24 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgb24 = image.pixels.rgb24;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .rgba32 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgba32 = image.pixels.rgba32;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .bgr24 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Bgr24 = image.pixels.bgr24;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .bgra32 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Bgra32 = image.pixels.bgra32;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, u8, u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .rgb48 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgb48 = image.pixels.rgb48;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u16, u16, u16, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .rgba64 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgba64 = image.pixels.rgba64;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u16, u16, u16, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .float32 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Colorf32 = image.pixels.float32;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(f32, f32, f32, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
    };
}
