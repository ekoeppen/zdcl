const a = .{
    .{
        .state = .outside_packet,
        .actions = &.{
            .{ .event = SYN, .new_state = .start_syn },
        },
    },
    .{
        .state = .start_syn,
        .actions = &.{
            .{ .event = DLE, .new_state = .start_dle },
            .{ .new_state = .outside_packet },
        },
    },
    .{
        .state = .start_dle,
        .actions = &.{
            .{ .event = STX, .action = .start_packet, .new_state = .inside_packet },
            .{ .new_state = .outside_packet },
        },
    },
    .{
        .state = .inside_packet,
        .actions = &.{
            .{ .event = DLE, .new_state = .dle_in_packet },
            .{ .action = .add_byte, .new_state = .inside_packet },
        },
    },
    .{
        .state = .dle_in_packet,
        .actions = &.{
            .{ .event = DLE, .action = .add_dle, .new_state = .inside_packet },
            .{ .event = ETX, .action = .update_calculated_crc, .new_state = .end_etx },
            .{ .new_state = .outside_packet },
        },
    },
    .{
        .state = .end_etx,
        .actions = &.{
            .{ .action = .reset_received_crc, .new_state = .end_crc1 },
        },
    },
    .{
        .state = .end_crc1,
        .actions = &.{
            .{ .action = .packet_received, .new_state = .packet_end },
        },
    },
    .{
        .state = .packet_end,
        .actions = &.{
            .{ .event = SYN, .new_state = .start_syn },
            .{ .new_state = .outside_packet },
        },
    },
};
