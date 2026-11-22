//! The four-corner cursor trail. Geometry is in grid-relative framebuffer pixels.
//! Algorithm reference: kitty/kitty/cursor_trail.c (Kovid Goyal and contributors).
const std = @import("std");

const Self = @This();
pub const Point = @Vector(2, f32);

pub const Rect = struct {
    min: Point,
    max: Point,

    fn corners(self: Rect) [4]Point {
        return .{
            self.min,
            .{ self.max[0], self.min[1] },
            .{ self.min[0], self.max[1] },
            self.max,
        };
    }
};

/// Render-thread sample sent to the native app thread. Rect coordinates are
/// framebuffer pixels with a top-left origin relative to the surface.
pub const Sample = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    cell_width: f32 = 0,
    cell_height: f32 = 0,
    fast_decay: f32 = 0.1,
    slow_decay: f32 = 0.4,
    hold_ms: u32 = 0,
    threshold_x: u32 = 2,
    threshold_y: u32 = 2,
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,
    alpha: u8 = 255,
    cursor_visible: bool = false,
    display_p3: bool = false,
};

pub const Output = extern struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
    opacity: f32,
    active: bool,
    pending: bool,
};

target: ?Rect = null,
target_surface: u64 = 0,
candidate_surface: u64 = 0,
candidate: ?Rect = null,
candidate_since: std.Io.Timestamp = .zero,
last_frame: std.Io.Timestamp = .zero,
dirty: bool = false,
active: bool = false,
opacity: f32 = 1,
corners: [4]Point = @splat(@splat(0)),

pub fn observe(self: *Self, rect: Rect, now: std.Io.Timestamp) void {
    self.observeSurface(0, rect, now);
}

pub fn observeSurface(self: *Self, surface_id: u64, rect: Rect, now: std.Io.Timestamp) void {
    if (self.candidate_surface == surface_id) if (self.candidate) |previous| {
        if (@reduce(.And, previous.min == rect.min) and
            @reduce(.And, previous.max == rect.max)) return;
    };
    self.candidate_surface = surface_id;
    self.candidate = rect;
    self.candidate_since = now;
    self.dirty = true;
    if (self.target == null) {
        self.target = rect;
        self.target_surface = surface_id;
        self.corners = rect.corners();
        self.dirty = false;
    }
}

pub fn advance(
    self: *Self,
    now: std.Io.Timestamp,
    cursor_visible: bool,
    hold_ms: u32,
    threshold: [2]u32,
    decay: [2]f32,
    cell_size: Point,
    screen_size: Point,
) void {
    if (self.target == null) return;
    if (self.dirty and self.candidate_since.durationTo(now).nanoseconds >=
        @as(i96, hold_ms) * std.time.ns_per_ms)
    {
        const rect = self.candidate.?;
        const surface_changed = self.target_surface != self.candidate_surface;
        self.target_surface = self.candidate_surface;
        self.target = rect;
        self.dirty = false;

        const movement = @round(@abs((rect.corners()[1] - self.corners[1]) / cell_size));
        const limit: Point = .{ @floatFromInt(threshold[0]), @floatFromInt(threshold[1]) };
        if (!self.active and !surface_changed and @reduce(.And, movement <= limit)) {
            self.corners = rect.corners();
        } else if (!self.active) {
            self.last_frame = self.candidate_since;
            self.active = true;
        }
    }

    if (!self.active) {
        if (cursor_visible) self.opacity = 1;
        return;
    }
    const rect = self.target.?;
    const goal = rect.corners();
    const center = (rect.min + rect.max) * @as(Point, @splat(0.5));
    const radius = length((rect.max - center) / screen_size);
    const dt = @as(f32, @floatFromInt(self.last_frame.durationTo(now).nanoseconds)) /
        std.time.ns_per_s;
    self.last_frame = now;
    const opacity_delta = dt / decay[1];
    self.opacity = if (cursor_visible)
        @min(1, self.opacity + opacity_delta)
    else
        @max(0, self.opacity - opacity_delta);
    if (self.opacity == 0 and !cursor_visible) {
        self.active = false;
        self.corners = goal;
        return;
    }

    var alignment: [4]f32 = undefined;
    for (goal, self.corners, &alignment) |destination, current, *value| {
        const delta = (destination - current) / screen_size;
        const distance = length(delta);
        value.* = if (distance < 0.000001)
            0
        else
            @reduce(.Add, delta * ((destination - center) / screen_size)) / (radius * distance);
    }

    const low = @reduce(.Min, @as(@Vector(4, f32), alignment));
    const high = @reduce(.Max, @as(@Vector(4, f32), alignment));
    var moving = false;
    for (goal, alignment, &self.corners) |destination, projection, *current| {
        const duration = if (high == low)
            decay[1]
        else
            decay[1] + (decay[0] - decay[1]) * (projection - low) / (high - low);
        const step = 1 - @exp2(-10 * dt / duration);
        current.* += (destination - current.*) * @as(Point, @splat(step));
        moving = moving or @reduce(.Or, @abs(destination - current.*) >= @as(Point, @splat(0.5)));
    }

    self.active = moving;
    if (!moving) self.corners = goal;
}

fn length(point: Point) f32 {
    return @sqrt(@reduce(.Add, point * point));
}

test "cursor trail waits, stretches, and settles" {
    var trail: Self = .{};
    const start: std.Io.Timestamp = .zero;
    const next: std.Io.Timestamp = .{ .nanoseconds = 100 * std.time.ns_per_ms };
    const done: std.Io.Timestamp = .{ .nanoseconds = std.time.ns_per_s };
    const original: Rect = .{ .min = .{ 0, 0 }, .max = .{ 10, 20 } };
    const destination: Rect = .{ .min = .{ 100, 0 }, .max = .{ 110, 20 } };
    trail.observe(original, start);
    trail.observe(destination, start);
    trail.advance(start, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expect(!trail.active);
    try std.testing.expect(trail.dirty);
    trail.advance(next, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expect(trail.active);
    try std.testing.expect(trail.corners[1][0] - 10 > trail.corners[0][0]);
    trail.advance(done, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expect(!trail.active);
    try std.testing.expectEqual(destination.corners(), trail.corners);
}

test "cursor trail ignores short jumps on both axes" {
    var trail: Self = .{};
    const now: std.Io.Timestamp = .zero;
    trail.observe(.{ .min = .{ 0, 0 }, .max = .{ 10, 20 } }, now);
    trail.observe(.{ .min = .{ 20, 20 }, .max = .{ 30, 40 } }, now);
    trail.advance(now, true, 0, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expect(!trail.active and !trail.dirty);
}

test "cursor trail matches Kitty's horizontal corner decay" {
    var trail: Self = .{};
    const start: std.Io.Timestamp = .zero;
    const frame: std.Io.Timestamp = .{ .nanoseconds = 20 * std.time.ns_per_ms };
    trail.observe(.{ .min = .{ 0, 0 }, .max = .{ 10, 20 } }, start);
    trail.observe(.{ .min = .{ 100, 0 }, .max = .{ 110, 20 } }, start);
    trail.advance(frame, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    // At 20 ms, the near edge has moved 75% of the way. The far
    // edge has moved about 29.289%, so the quad has stretched.
    try std.testing.expectApproxEqAbs(@as(f32, 85), trail.corners[1][0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 29.28932), trail.corners[0][0], 0.001);
}

test "cursor trail fades when the application hides the cursor" {
    var trail: Self = .{};
    const start: std.Io.Timestamp = .zero;
    const frame: std.Io.Timestamp = .{ .nanoseconds = 20 * std.time.ns_per_ms };
    const hidden: std.Io.Timestamp = .{ .nanoseconds = 40 * std.time.ns_per_ms };
    trail.observe(.{ .min = .{ 0, 0 }, .max = .{ 10, 20 } }, start);
    trail.observe(.{ .min = .{ 100, 0 }, .max = .{ 110, 20 } }, start);
    trail.advance(frame, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    trail.advance(hidden, false, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), trail.opacity, 0.001);
}

test "cursor trail bypasses the distance threshold when a split gains focus" {
    var trail: Self = .{};
    const start: std.Io.Timestamp = .zero;
    const frame: std.Io.Timestamp = .{ .nanoseconds = 20 * std.time.ns_per_ms };
    trail.observeSurface(1, .{ .min = .{ 0, 0 }, .max = .{ 10, 20 } }, start);
    trail.observeSurface(2, .{ .min = .{ 10, 0 }, .max = .{ 20, 20 } }, start);
    trail.advance(frame, true, 1, .{ 2, 2 }, .{ 0.1, 0.4 }, .{ 10, 20 }, .{ 1920, 1080 });
    try std.testing.expect(trail.active);
    try std.testing.expectEqual(@as(u64, 2), trail.target_surface);
}
