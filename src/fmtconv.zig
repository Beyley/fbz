const std = @import("std");
const img = @import("zigimg/zigimg.zig");

const Image = img.Image;

/// Converts a 24-bit RGB color to a 16-bit color, for use in the framebuffer.
// fn make16Color(r: u8, g: u8, b: u8) u16 {
//     return (((@as(u16, r >> 3) & 31) << 11) |
//         ((@as(u16, g >> 2) & 63) << 5) |
//         (@as(u16, b >> 3) & 31));
// }

fn make16Color(comptime SourceType: type, r: anytype, g: anytype, b: anytype) u16 {
    @setFloatMode(std.builtin.FloatMode.Optimized);
    if (SourceType == u8) {
        return (((@as(u16, r >> 3) & 31) << 11) |
            ((@as(u16, g >> 2) & 63) << 5) |
            (@as(u16, b >> 3) & 31));
    } else {
        //assuming SourceType is an integer convert the values to u8 range 0-255 using the max
        //value of the SourceType
        const max = @as(SourceType, @as(SourceType, 1) << @typeInfo(SourceType).Int.bits);
        const maxU8 = @as(SourceType, 255);

        const r8 = @as(SourceType, @intCast(SourceType, @floatCast(f32, r) / max * maxU8));
        const g8 = @as(SourceType, @intCast(SourceType, @floatCast(f32, g) / max * maxU8));
        const b8 = @as(SourceType, @intCast(SourceType, @floatCast(f32, b) / max * maxU8));

        return make16Color(u8, r8, g8, b8);
    }
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
        .rgb555 => @panic("TODO: rgb555"),
        .rgb24 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgb24 = image.pixels.rgb24;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .rgba32 => {
            var pixels = try allocator.alloc(u16, image.width * image.height);

            var old_pixels: []img.color.Rgba32 = image.pixels.rgba32;
            for (pixels, 0..) |*pixel, i| {
                pixel.* = make16Color(u8, old_pixels[i].r, old_pixels[i].g, old_pixels[i].b);
            }

            return pixels;
        },
        .bgr24 => @panic("TODO: bgr24"),
        .bgra32 => @panic("TODO: bgra32"),
        .rgb48 => @panic("TODO: rgb48"),
        .rgba64 => @panic("TODO: rgba64"),
        .float32 => @panic("TODO: float32"),
    };
}
