const std = @import("std");

pub fn main() !void {
    const timestamp: i64 = 1704067200; // 2024-01-01 00:00:00 UTC
    const date = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const year_day = date.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    
    std.debug.print("Year: {d}\n", .{year_day.year});
    std.debug.print("Month: {d}\n", .{month_day.month.numeric()});
    
    // Try to print all fields
    std.debug.print("MonthDay fields: {any}\n", .{month_day});
}
