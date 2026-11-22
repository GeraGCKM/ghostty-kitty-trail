const std = @import("std");
const Allocator = std.mem.Allocator;
const formatterpkg = @import("formatter.zig");
const Config = @import("Config.zig");

pub const Decay = struct {
    values: [2]f32 = .{ 0.1, 0.4 },

    pub fn parseCLI(input: ?[]const u8) !Decay {
        var parts = std.mem.tokenizeAny(u8, input orelse return error.ValueRequired, " \t");
        const fast = std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidValue) catch return error.InvalidValue;
        const slow = std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidValue) catch return error.InvalidValue;
        if (parts.next() != null or !std.math.isFinite(fast) or !std.math.isFinite(slow) or
            fast <= 0 or slow <= 0) return error.InvalidValue;
        return .{ .values = .{ fast, @max(fast, slow) } };
    }

    pub fn formatEntry(self: Decay, formatter: formatterpkg.EntryFormatter) !void {
        var buf: [128]u8 = undefined;
        try formatter.formatEntry([]const u8, try std.fmt.bufPrint(&buf, "{d} {d}", .{ self.values[0], self.values[1] }));
    }

    pub fn clone(self: Decay, _: Allocator) error{}!Decay {
        return self;
    }

    pub fn equal(self: Decay, other: Decay) bool {
        return std.meta.eql(self, other);
    }
};

pub const Threshold = struct {
    values: [2]u32 = .{ 2, 2 },

    pub fn parseCLI(input: ?[]const u8) !Threshold {
        var parts = std.mem.tokenizeAny(u8, input orelse return error.ValueRequired, " \t");
        const x = std.fmt.parseInt(u32, parts.next() orelse return error.InvalidValue, 10) catch return error.InvalidValue;
        const y = if (parts.next()) |part| std.fmt.parseInt(u32, part, 10) catch return error.InvalidValue else x;
        if (parts.next() != null) return error.InvalidValue;
        return .{ .values = .{ x, y } };
    }

    pub fn formatEntry(self: Threshold, formatter: formatterpkg.EntryFormatter) !void {
        var buf: [32]u8 = undefined;
        try formatter.formatEntry([]const u8, try std.fmt.bufPrint(&buf, "{d} {d}", .{ self.values[0], self.values[1] }));
    }

    pub fn clone(self: Threshold, _: Allocator) error{}!Threshold {
        return self;
    }

    pub fn equal(self: Threshold, other: Threshold) bool {
        return std.meta.eql(self, other);
    }
};

pub const Color = struct {
    value: ?Config.Color = null,

    pub fn parseCLI(input: ?[]const u8) !Color {
        const value = input orelse return error.ValueRequired;
        if (std.ascii.eqlIgnoreCase(value, "none")) return .{};
        return .{ .value = try Config.Color.parseCLI(value) };
    }

    pub fn formatEntry(self: Color, formatter: formatterpkg.EntryFormatter) !void {
        if (self.value) |color| return color.formatEntry(formatter);
        try formatter.formatEntry([]const u8, "none");
    }

    pub fn clone(self: Color, _: Allocator) error{}!Color {
        return self;
    }

    pub fn equal(self: Color, other: Color) bool {
        return std.meta.eql(self, other);
    }
};
