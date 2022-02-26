const std = @import("std");
const hexdump = @import("../utils/hexdump.zig");
const queue = @import("../utils/queue.zig");

pub const DockCommand = enum(u32) {
    last_app_command = 0x32323232,
    newt = 0x6e657774,
    dock = 0x646f636b,
    longdata = 0x6c647461,
    ref_result = 0x72656620,
    query = 0x71757279,
    cursor_goto_key = 0x676f746f,
    cursor_map = 0x636d6170,
    cursor_entry = 0x63727372,
    cursor_move = 0x6d6f7665,
    cursor_next = 0x6e657874,
    cursor_prev = 0x70726576,
    cursor_reset = 0x72736574,
    cursor_reset_to_end = 0x72656e64,
    cursor_count_entries = 0x636e7420,
    cursor_which_end = 0x77686368,
    cursor_free = 0x63667265,
    keyboard_char = 0x6b626463,
    desktop_info = 0x64696e66,
    keyboard_string = 0x6b626473,
    start_keyboard_passthrough = 0x6b796264,
    default_store = 0x64667374,
    app_names = 0x6170706e,
    import_parameter_slip_result = 0x69736c72,
    package_info = 0x70696e66,
    set_base_id = 0x62617365,
    backup_ids = 0x62696473,
    backup_soup_done = 0x6273646e,
    soup_not_dirty = 0x6e646972,
    synchronize = 0x73796e63,
    call_result = 0x63726573,
    remove_package = 0x726d7670,
    result_string = 0x72657373,
    source_version = 0x73766572,
    add_entry_with_unique_id = 0x61756e69,
    get_package_info = 0x6770696e,
    get_default_store = 0x67646673,
    create_default_soup = 0x63647370,
    get_app_names = 0x67617070,
    reg_protocol_extension = 0x70657874,
    remove_protocol_extension = 0x72706578,
    set_store_signature = 0x73736967,
    set_soup_signature = 0x73736f73,
    import_parameters_slip = 0x69736c70,
    get_password = 0x67707764,
    send_soup = 0x736e6473,
    backup_soup = 0x626b7370,
    set_store_name = 0x73736e61,
    call_global_function = 0x6367666e,
    call_root_method = 0x63726d64,
    set_vbo_compression = 0x6376626f,
    restore_patch = 0x72706174,
    operation_done = 0x6f70646e,
    operation_canceled = 0x6f70636e,
    op_canceled_ack = 0x6f636161,
    ref_test = 0x72747374,
    unknown_command = 0x756e6b6e,
    password = 0x70617373,
    newton_name = 0x6e616d65,
    newton_info = 0x6e696e66,
    which_icons = 0x7769636e,
    request_to_sync = 0x7373796e,
    sync_options = 0x736f7074,
    get_sync_options = 0x6773796e,
    sync_results = 0x73726573,
    set_store_get_names = 0x7373676e,
    set_soup_get_info = 0x73736769,
    get_changed_index = 0x63696478,
    get_changed_info = 0x63696e66,
    request_to_browse = 0x72746272,
    get_devices = 0x67646576,
    get_default_path = 0x64707468,
    get_files_and_folders = 0x6766696c,
    set_path = 0x73707468,
    get_file_info = 0x6766696e,
    internal_store = 0x6973746f,
    resolve_alias = 0x72616c69,
    get_filters = 0x67666c74,
    set_filter = 0x73666c74,
    set_drive = 0x73647276,
    devices = 0x64657673,
    filters = 0x66696c74,
    path = 0x70617468,
    files_and_folders = 0x66696c65,
    file_info = 0x66696e66,
    get_internal_store = 0x67697374,
    alias_resolved = 0x616c6972,
    import_file = 0x696d7074,
    set_translator = 0x7472616e,
    translator_list = 0x74726e6c,
    importing = 0x64696d70,
    soups_changed = 0x73636867,
    set_store_to_default = 0x73646566,
    load_package_file = 0x6c70666c,
    restore_file = 0x7273666c,
    get_restore_options = 0x67726f70,
    restore_all = 0x72616c6c,
    restore_options = 0x726f7074,
    restore_package = 0x72706b67,
    request_to_restore = 0x72727374,
    request_to_install = 0x72696e73,
    request_to_dock = 0x7274646b,
    current_time = 0x74696d65,
    store_names = 0x73746f72,
    soup_names = 0x736f7570,
    soup_ids = 0x73696473,
    changed_ids = 0x63696473,
    result = 0x64726573,
    added_id = 0x61646964,
    entry = 0x656e7472,
    package_id_list = 0x70696473,
    package = 0x61706b67,
    index_description = 0x696e6478,
    inheritance = 0x64696e68,
    patches = 0x70617463,
    last_sync_time = 0x73746d65,
    get_store_names = 0x6773746f,
    get_soup_names = 0x67657473,
    set_current_store = 0x7373746f,
    set_current_soup = 0x73736f75,
    get_soup_ids = 0x67696473,
    delete_entries = 0x64656c65,
    add_entry = 0x61646465,
    return_entry = 0x72657465,
    return_changed_entry = 0x7263656e,
    empty_soup = 0x65736f75,
    delete_soup = 0x64736f75,
    load_package = 0x6c706b67,
    get_package_ids = 0x67706964,
    backup_packages = 0x62706b67,
    disconnect = 0x64697363,
    delete_all_packages = 0x64706b67,
    get_index_description = 0x67696e64,
    create_soup = 0x63736f70,
    get_inheritance = 0x67696e68,
    set_timeout = 0x7374696d,
    get_patches = 0x67706174,
    delete_pkg_dir = 0x64706b64,
    get_soup_info = 0x6773696e,
    changed_entry = 0x63656e74,
    test_cmd = 0x74657374,
    hello = 0x68656c6f,
    soup_info = 0x73696e66,
    _,
};

pub const AppEventType = enum {
    connected,
    disconnected,
};

pub const EventSource = enum {
    serial,
    mnp,
    dock,
    app,
    timer,
};

const EventDirection = enum {
    in,
    out,
};

fn setPacketData(comptime T: type, packet: *T, data: []const u8, allocator: std.mem.Allocator) !void {
    packet.length = @truncate(u32, data.len);
    packet.data = try allocator.alloc(u8, packet.length);
    std.mem.copy(u8, packet.data, data);
}

pub const SerialPacket = struct {
    direction: EventDirection,
    data: []u8 = undefined,
    length: u32 = undefined,

    pub fn format(self: SerialPacket, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "{} {}\n", .{ self.direction, self.length });
        try hexdump.toWriter(self.data[0..self.length], writer);
    }

    pub fn init(direction: EventDirection, data: []const u8, allocator: std.mem.Allocator) !SerialPacket {
        var packet: SerialPacket = .{ .direction = direction };
        try setPacketData(SerialPacket, &packet, data, allocator);
        return packet;
    }

    pub fn deinit(self: *const SerialPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const MnpPacket = struct {
    direction: EventDirection,
    data: []u8 = undefined,
    length: u32 = undefined,

    pub fn format(self: MnpPacket, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "{}\n", .{self.direction});
        try hexdump.toWriter(self.data[0..self.length], writer);
    }

    pub fn init(direction: EventDirection, data: []const u8, allocator: std.mem.Allocator) !MnpPacket {
        var packet: MnpPacket = .{ .direction = direction };
        try setPacketData(MnpPacket, &packet, data, allocator);
        return packet;
    }

    pub fn deinit(self: *const MnpPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const DockPacket = struct {
    direction: EventDirection,
    command: DockCommand,
    length: u32 = undefined,
    data: []u8 = undefined,

    pub fn format(self: DockPacket, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "{} {}\n", .{ self.direction, self.command });
        try hexdump.toWriter(self.data[0..self.length], writer);
    }

    pub fn init(command: DockCommand, direction: EventDirection, data: []const u8, allocator: std.mem.Allocator) !DockPacket {
        var packet: DockPacket = .{ .direction = direction, .command = command };
        try setPacketData(DockPacket, &packet, data, allocator);
        return packet;
    }

    pub fn deinit(self: *const DockPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const AppEvent = struct {
    direction: EventDirection,
    event: AppEventType,
    length: u32 = undefined,
    data: []u8 = undefined,

    pub fn init(event: AppEventType, direction: EventDirection, data: []const u8, allocator: std.mem.Allocator) !DockPacket {
        var packet: AppEvent = .{ .direction = direction, .event = event };
        try setPacketData(AppEvent, &packet, data, allocator);
        return packet;
    }

    pub fn deinit(self: *const AppEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const TimerEvent = struct {
    source: EventSource,
    delay: u32,
};

const StackEventType = enum {
    serial,
    mnp,
    dock,
    timer,
    app,
};

pub const StackEvent = union(StackEventType) {
    serial: SerialPacket,
    mnp: MnpPacket,
    dock: DockPacket,
    timer: TimerEvent,
    app: AppEvent,

    pub fn deinit(self: StackEvent, allocator: std.mem.Allocator) void {
        switch (self) {
            .app => |app| app.deinit(allocator),
            .dock => |dock| dock.deinit(allocator),
            .mnp => |mnp| mnp.deinit(allocator),
            .serial => |serial| serial.deinit(allocator),
            .timer => {},
        }
    }
};

var events: queue.Queue(StackEvent) = undefined;
var mutex: std.Thread.Mutex = undefined;
var available: std.Thread.Semaphore = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    events = .{ .allocator = allocator };
    mutex = .{};
    available = .{};
}

pub fn has_available() bool {
    available.mutex.lock();
    defer available.mutex.unlock();
    return available.permits > 0;
}

pub fn enqueue(event: StackEvent) !void {
    mutex.lock();
    defer mutex.unlock();
    try events.enqueue(event);
    available.post();
}

pub fn dequeue() ?StackEvent {
    available.wait();
    mutex.lock();
    mutex.unlock();
    return events.dequeue();
}
