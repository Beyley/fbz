const std = @import("std");

const fs = std.fs;

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
