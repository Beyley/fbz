const std = @import("std");
const img = @import("zigimg/zigimg.zig");
const clap = @import("zig-clap/clap.zig");

const Image = img.Image;

const debug = std.debug;
const io = std.io;
const fs = std.fs;

const Framebuffer = @import("fb.zig");
const FormatConvert = @import("fmtconv.zig");

var silent: bool = false;

pub fn log(comptime format: []const u8, args: anytype) void {
    if (silent)
        return;

    const stdout = std.io.getStdOut().writer();

    std.io.getStdOut().lock(.Exclusive) catch {};
    defer std.io.getStdOut().unlock();
    nosuspend stdout.print(format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("Memory leak detected!");
    var allocator = gpa.allocator();

    // Parse the CLI parameters that will be used
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit.
        \\-f, --framebuffer <str> The framebuffer device to use. [default is `/dev/fb0`]
        \\-s, --silent      Don't print anything to stdout.
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();
    var args = res.args;

    if (args.silent != 0)
        silent = true;

    //If the user specified the help flag, print the help message and exit
    if (args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    //The default framebuffer
    var framebuffer_path: []const u8 = "/dev/fb0";

    //If the user specified a framebuffer, use that instead
    if (args.framebuffer) |fb|
        framebuffer_path = fb;

    //If the user didn't specify an image, print an error and exit
    if (res.positionals.len != 1) {
        debug.print("You need to specify an image!\n", .{});
        return;
    }

    //get the file extension
    var extension = std.fs.path.extension(res.positionals[0]);

    //try to open the png file
    var file = try std.fs.cwd().openFile(res.positionals[0], .{});

    //create the image stream
    var stream: Image.Stream = .{ .file = file };

    //check the file extension
    if (std.mem.eql(u8, extension, ".png")) {
        log("Loading PNG file", .{});

        //load the image
        var image: Image = try img.png.load(&stream, allocator, .{ .temp_allocator = allocator });
        defer image.deinit();

        log("Loaded PNG file with size {d}x{d}", .{ image.width, image.height });

        try Framebuffer.setCursorBlink(false);

        try displayImage(allocator, framebuffer_path, &image);
    } else {
        std.log.err("Unsupported file format: {s}\n", .{extension});
        return;
    }
}

///Centers an image from a top left origin
fn centerImage(image: *Image, fb_info: Framebuffer.FramebufferInfo) struct { x: usize, y: usize } {
    var x = (fb_info.width - image.width) / 2;
    var y = (fb_info.height - image.height) / 2;

    return .{ .x = x, .y = y };
}

fn displayImage(allocator: std.mem.Allocator, framebuffer: []const u8, image: *Image) !void {
    var file: fs.File = try fs.openFileAbsolute(framebuffer, .{ .mode = .read_write });
    defer file.close();

    var fb_info = try Framebuffer.getFramebufferInfo(file);

    var coords = centerImage(image, fb_info);
    log("Drawing image at {d}, {d}", .{ coords.x, coords.y });

    //we dont support, scaling images, so lets die if its too tall or too wide
    if (image.width > fb_info.width or image.height > fb_info.height) {
        return error.ImageTooWideOrTall;
    }

    var pixels: []u16 = try FormatConvert.convertToRGB565(allocator, image);
    defer allocator.free(pixels);
    var pixelsU8: [*]u8 = @ptrCast([*]u8, pixels);

    var fbu8 = try Framebuffer.mapFramebuffer(file, fb_info);

    var fb = @ptrCast([*]u8, @alignCast(@alignOf(u8), fbu8));

    if (image.width != fb_info.width or image.height != fb_info.height) {
        Framebuffer.clearFramebuffer(fb, fb_info);
    }

    var ptrSrc = pixelsU8;
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
}
