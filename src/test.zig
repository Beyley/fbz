const std = @import("std");
const testing = std.testing;

const FormatConvert = @import("fmtconv.zig");

test "shiftLeftShiftingInLSB" {
    var x: u8 = 0b00001111;
    var y = FormatConvert.shiftLeftShiftingInLSB(u8, x, 1);
    try testing.expect(y == 0b00011111);

    x = 0b00001110;
    y = FormatConvert.shiftLeftShiftingInLSB(u8, x, 1);
    try testing.expect(y == 0b00011100);

    x = 0b00001100;
    y = FormatConvert.shiftLeftShiftingInLSB(u8, x, 2);
    try testing.expect(y == 0b00110000);

    x = 0b00001101;
    y = FormatConvert.shiftLeftShiftingInLSB(u8, x, 2);
    try testing.expect(y == 0b00110111);

    x = 0b00000001;
    y = FormatConvert.shiftLeftShiftingInLSB(u8, x, 3);
    try testing.expectEqual(@as(u8, 0b00001111), y);
}
