const std = @import("std");
const img = @import("zigimg/zigimg.zig");
const fs = std.fs;

const Image = img.Image;

const FormatConvert = @import("fmtconv.zig");
const log = @import("main.zig").log;

const c = @cImport({
    @cInclude("linux/fb.h");
    @cInclude("sys/mman.h");
});

pub const FramebufferInfo = struct {
    ///width of the framebuffer in pixels
    width: usize,
    ///height of the framebuffer in pixels
    height: usize,
    ///bits per pixel
    bits_per_pixel: u8,
    ///bytes per line
    line_length: usize,
    ///length of the framebuffer in bytes
    mem_length: usize,
};

const Errors = error{
    ScreenInfoFail,
    ScreenFixFail,
};

pub fn getFramebufferInfo(file: fs.File) !FramebufferInfo {
    var info: c.fb_var_screeninfo = undefined;
    if (std.c.ioctl(file.handle, c.FBIOGET_VSCREENINFO, &info) != 0) {
        return Errors.ScreenInfoFail;
    }

    var fix: c.fb_fix_screeninfo = undefined;
    if (std.c.ioctl(file.handle, c.FBIOGET_FSCREENINFO, &fix) != 0) {
        return Errors.ScreenFixFail;
    }

    var pix_x = (fix.line_length * 8) / info.bits_per_pixel;
    var pix_y = fix.smem_len / fix.line_length;

    return .{
        .width = pix_x,
        .height = pix_y,
        .bits_per_pixel = @intCast(u8, info.bits_per_pixel),
        .line_length = fix.line_length,
        .mem_length = fix.smem_len,
    };
}

pub fn mapFramebuffer(file: fs.File, info: FramebufferInfo) !*anyopaque {
    const mem = std.c.mmap(null, info.mem_length, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, file.handle, 0);
    if (mem == c.MAP_FAILED) {
        return error.OutOfMemory;
    }

    return mem;
}

pub fn clearFramebuffer(fb: [*]u8, info: FramebufferInfo) void {
    for (fb[0..info.mem_length]) |*byte| {
        byte.* = 0;
    }
}

pub fn setCursorBlink(state: bool) !void {
    var file: fs.File = try fs.openFileAbsolute("/sys/class/graphics/fbcon/cursor_blink", .{ .mode = .read_write });
    defer file.close();

    if (state) {
        try file.writer().print("1", .{});
    } else {
        try file.writer().print("0", .{});
    }
}

///Centers an image from a top left origin
fn centerImage(image: DisplayImage, fb_info: FramebufferInfo) struct { x: usize, y: usize } {
    var x = (fb_info.width - image.width) / 2;
    var y = (fb_info.height - image.height) / 2;

    return .{ .x = x, .y = y };
}

/// Converts an image to RGB565, the caller owns the memory
fn convertImage(allocator: std.mem.Allocator, image: *Image) ![]u16 {
    var pixels: []u16 = try FormatConvert.convertToRGB565(allocator, image);

    return pixels;
}

pub const DisplayImage = struct {
    /// The converted image data, in RGB565 format
    data: []u16,
    /// The width of the image
    width: usize,
    /// The height of the image
    height: usize,
};

const DisplayImageSettings = struct {
    /// Whether to disable clearing of the framebuffer before displaying the image
    never_clear_fb: bool = false,
};

/// Opens the framebuffer, maps it to memory, and returns a pointer to the framebuffer
pub fn prepareFramebuffer(framebuffer_path: []const u8) !struct { info: FramebufferInfo, fb_ptr: [*]u8, file: fs.File } {
    var file: fs.File = try fs.openFileAbsolute(framebuffer_path, .{ .mode = .read_write });

    var fb_info = try getFramebufferInfo(file);

    //get a map of the framebuffer
    var fb_ptr_raw = try mapFramebuffer(file, fb_info);
    var fb = @ptrCast([*]u8, @alignCast(@alignOf(u8), fb_ptr_raw));

    return .{ .info = fb_info, .fb_ptr = fb, .file = file };
}

pub fn displayImage(allocator: std.mem.Allocator, fb: [*]u8, fb_info: FramebufferInfo, image: DisplayImage, settings: DisplayImageSettings) !void {
    var coords = centerImage(image, fb_info);
    log("Drawing image at {d}, {d}", .{ coords.x, coords.y });

    //we dont support, scaling images, so lets die if its too tall or too wide
    if (image.width > fb_info.width or image.height > fb_info.height) {
        return error.ImageTooWideOrTall;
    }

    //get a pointer to the image data, in u8 format
    var image_pixels: [*]u8 = @ptrCast([*]u8, image.data);

    //if the image is smaller than the framebuffer, clear the framebuffer, unless we are told never to clear
    if ((image.width != fb_info.width or image.height != fb_info.height) and !settings.never_clear_fb) {
        clearFramebuffer(fb, fb_info);
    }

    var ptrSrc = image_pixels;
    var ptrDst = fb + (fb_info.line_length * coords.y) + (coords.x * @sizeOf(u16));
    for (0..image.height) |y| {
        var fb_start = y * fb_info.width;
        var img_start = y * image.width;

        var fb_end = fb_start + image.width;
        _ = fb_end;
        var img_end = img_start + image.width;
        _ = img_end;

        @memcpy(ptrDst, ptrSrc, image.width * @sizeOf(u16));
        ptrSrc += image.width * @sizeOf(u16);
        ptrDst += fb_info.line_length;
    }

    _ = allocator;
}
