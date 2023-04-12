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

fn intMax(comptime Type: type) Type {
    return @as(Type, @as(Type, 1) << @typeInfo(Type).Int.bits) - 1;
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
                destRed = @intCast(dest, r << shift.amount);
            } else {
                destRed = @as(dest, r);
            }
        },
        else => @compileError("Converting from that integer format is not supported!"),
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
                destGreen = @intCast(dest, g << shift.amount);
            } else {
                destGreen = @as(dest, g);
            }
        },
        else => @compileError("Converting from that integer format is not supported!"),
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
                destBlue = @intCast(dest, b << shift.amount);
            } else {
                destBlue = @as(dest, b);
            }
        },
        else => @compileError("Converting from that integer format is not supported!"),
    }

    return (((@as(u16, destRed)) << 11) |
        ((@as(u16, destGreen)) << 5) |
        (@as(u16, destBlue)));
}

pub fn convertToRGB565(allocator: std.mem.Allocator, image: *img.Image) ![]u16 {
    return switch (image.pixelFormat()) {
        .invalid => @panic("Invalid format passed into convertToRGB565"),
        .indexed1 => @panic("TODO: indexed1"),
        .indexed2 => @panic("TODO: indexed2"),
        .indexed4 => @panic("TODO: indexed4"),
        .indexed8 => @panic("TODO: indexed8"),
        .indexed16 => @panic("TODO: indexed16"),
        .grayscale1 => @panic("TODO: grayscale1"),
        .grayscale2 => @panic("TODO: grayscale2"),
        .grayscale4 => @panic("TODO: grayscale4"),
        .grayscale8 => @panic("TODO: grayscale8"),
        .grayscale16 => @panic("TODO: grayscale16"),
        .grayscale8Alpha => @panic("TODO: grayscale8Alpha"),
        .grayscale16Alpha => @panic("TODO: grayscale16Alpha"),
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
        .float32 => @panic("TODO: float32"),
    };
}
