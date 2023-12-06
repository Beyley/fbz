const std = @import("std");
const img = @import("zigimg");
const clap = @import("zig-clap");

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

    std.io.getStdOut().lock(.exclusive) catch {};
    defer std.io.getStdOut().unlock();
    nosuspend stdout.print(format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Memory leak detected!");
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
    const args = res.args;

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
    if (res.positionals.len == 1) {
        //get the file extension
        const extension = std.fs.path.extension(res.positionals[0]);

        //try to open the image file
        const file = try std.fs.cwd().openFile(res.positionals[0], .{});

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

            try displaySingleImage(allocator, framebuffer_path, &image);
        } else if (std.mem.eql(u8, extension, ".bmp")) {
            log("Loading BMP file", .{});

            //load the image
            var image: Image = try img.bmp.BMP.readImage(allocator, &stream);
            defer image.deinit();

            log("Loaded BMP file with size {d}x{d}", .{ image.width, image.height });

            try Framebuffer.setCursorBlink(false);

            try displaySingleImage(allocator, framebuffer_path, &image);
        } else if (std.mem.eql(u8, extension, ".qoi")) {
            log("Loading QOI file", .{});

            //load the image
            var image: Image = try img.qoi.QOI.readImage(allocator, &stream);
            defer image.deinit();

            log("Loaded QOI file with size {d}x{d}", .{ image.width, image.height });

            try Framebuffer.setCursorBlink(false);

            try displaySingleImage(allocator, framebuffer_path, &image);
        } else if (std.mem.eql(u8, extension, ".tga")) {
            log("Loading TGA file", .{});

            //load the image
            var image: Image = try img.tga.TGA.readImage(allocator, &stream);
            defer image.deinit();

            log("Loaded TGA file with size {d}x{d}", .{ image.width, image.height });

            try Framebuffer.setCursorBlink(false);

            try displaySingleImage(allocator, framebuffer_path, &image);
        } else {
            std.log.err("Unsupported file format: {s}\n", .{extension});
            return;
        }
        return;
    }

    if (res.positionals.len > 1) {
        var display_images = try allocator.alloc(Framebuffer.DisplayImage, res.positionals.len);
        defer allocator.free(display_images);

        for (res.positionals, 0..) |positional, i| {
            log("Loading image {s}. {d}/{d}...", .{ positional, i + 1, res.positionals.len });

            //try to open the file
            var file = try std.fs.cwd().openFile(positional, .{});
            defer file.close();

            //create the image stream
            var stream: Image.Stream = .{ .file = file };

            //load the image
            var image: Image = try img.png.load(&stream, allocator, .{ .temp_allocator = allocator });
            defer image.deinit();

            display_images[i].data = try FormatConvert.convertToRGB565(allocator, &image);
            display_images[i].width = image.width;
            display_images[i].height = image.height;

            log("Loaded image {s} with size {d}x{d}. {d}/{d}", .{ positional, image.width, image.height, i + 1, res.positionals.len });
        }

        //Free the converted image data
        defer for (display_images) |image| {
            allocator.free(image.data);
        };

        //Disable cursor blinking on the framebuffer
        try Framebuffer.setCursorBlink(false);

        const fb = try Framebuffer.open(framebuffer_path);
        defer fb.file.close();

        for (display_images) |image| {
            //HACK: This is a hack to slow down the display of images because std.time.sleep() is inconsistent in oc2
            //NOTE: at 100MHz, 4 iterations is about 0.5 seconds
            for (0..4) |_| {
                try Framebuffer.displayImage(fb, image, .{ .never_clear_fb = true });
            }
        }

        return;
    }

    log("No image specified...", .{});
}

fn displaySingleImage(allocator: std.mem.Allocator, framebuffer_path: []const u8, image: *Image) !void {
    const fb = try Framebuffer.open(framebuffer_path);
    defer fb.file.close();

    const pixels: []img.color.Rgb565 = try FormatConvert.convertToRGB565(allocator, image);
    defer allocator.free(pixels);

    try Framebuffer.displayImage(fb, .{ .data = pixels, .width = image.width, .height = image.height }, .{});
}
