const std = @import("std");
const img = @import("zigimg");
const fs = std.fs;

const Image = img.Image;

const FormatConvert = @import("fmtconv.zig");
const log = @import("main.zig").log;

const c = @cImport({
    @cInclude("linux/fb.h");
    @cInclude("sys/mman.h");
});

const Self = @This();

/// The width of the framebuffer in pixels
width: usize,
/// The height of the framebuffer in pixel
height: usize,
/// The amount of bits per pixel
bits_per_pixel: u8,
/// Bytes per line
bytes_per_line: usize,
/// The contents of the framebuffer
contents: []img.color.Rgb565,
/// The file handle of the framebuffer
file: std.fs.File,

const Errors = error{
    ScreenInfoFail,
    ScreenFixFail,
};

fn clearFramebuffer(fb: Self) void {
    @memset(fb.contents, .{ .r = 0, .g = 0, .b = 0 });
}

///Sets the state of the cursor blink on the framebuffer console
pub fn setCursorBlink(state: bool) !void {
    var file: fs.File = try fs.openFileAbsolute("/sys/class/graphics/fbcon/cursor_blink", .{ .mode = .read_write });
    defer file.close();

    const writer = file.writer();
    if (state) {
        try writer.print("1", .{});
    } else {
        try writer.print("0", .{});
    }
}

///Centers an image from a top left origin
fn centerImage(image: DisplayImage, fb: Self) @Vector(2, usize) {
    const x = (fb.width - image.width) / 2;
    const y = (fb.height - image.height) / 2;

    return .{ x, y };
}

/// Converts an image to RGB565, the caller owns the memory
fn convertImage(allocator: std.mem.Allocator, image: *Image) ![]u16 {
    const pixels: []u16 = try FormatConvert.convertToRGB565(allocator, image);

    return pixels;
}

pub const DisplayImage = struct {
    /// The converted image data, in RGB565 format
    data: []img.color.Rgb565,
    /// The width of the image
    width: usize,
    /// The height of the image
    height: usize,
};

const DisplayImageSettings = struct {
    /// Whether to disable clearing of the framebuffer before displaying the image
    never_clear_fb: bool = false,
};

pub fn open(path: []const u8) !Self {
    const file: fs.File = try fs.openFileAbsolute(path, .{ .mode = .read_write });

    var info: c.fb_var_screeninfo = undefined;
    if (std.c.ioctl(file.handle, c.FBIOGET_VSCREENINFO, &info) != 0) {
        return Errors.ScreenInfoFail;
    }

    var fix: c.fb_fix_screeninfo = undefined;
    if (std.c.ioctl(file.handle, c.FBIOGET_FSCREENINFO, &fix) != 0) {
        return Errors.ScreenFixFail;
    }

    const fb_ptr: [*]u16 = @alignCast(@ptrCast(std.c.mmap(null, fix.smem_len, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, file.handle, 0)));
    if (@as(*anyopaque, fb_ptr) == c.MAP_FAILED) {
        return error.OutOfMemory;
    }

    return .{
        .width = info.xres,
        .height = info.yres,
        .bits_per_pixel = @intCast(info.bits_per_pixel),
        .bytes_per_line = fix.line_length,
        .contents = @ptrCast(fb_ptr[0..@divExact(fix.smem_len, 2)]),
        .file = file,
    };
}

pub fn displayImage(fb: Self, image: DisplayImage, settings: DisplayImageSettings) !void {
    const coords = centerImage(image, fb);
    log("Drawing image at {d}", .{coords});

    //we dont support, scaling images, so lets die if its too tall or too wide
    if (image.width > fb.width or image.height > fb.height) {
        return error.ImageTooWideOrTall;
    }

    //if the image is smaller than the framebuffer, clear the framebuffer, unless we are told never to clear
    if ((image.width != fb.width or image.height != fb.height) and !settings.never_clear_fb) {
        clearFramebuffer(fb);
    }

    //If the image width matches the framebuffer width, optimize down to a single memcpy
    if (image.width == fb.width) {
        const fb_start = fb.width * coords[1];

        @memcpy(fb.contents[fb_start .. fb_start + (image.height * image.width)], image.data);

        // @memcpy(fb.contents, image.data);
        return;
    }

    for (0..image.height) |y| {
        const fb_start = fb.width * (y + coords[1]) + coords[0];

        @memcpy(
            fb.contents[fb_start .. fb_start + image.width],
            image.data[image.width * y .. image.width * y + image.width],
        );
    }
}
