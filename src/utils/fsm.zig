pub fn Action(comptime E: type, comptime S: type, comptime A: type) type {
    return struct {
        event: ?E = null,
        action: ?A = null,
        new_state: ?S = null,
    };
}

pub fn Transition(comptime E: type, comptime S: type, comptime A: type) type {
    return struct {
        state: ?S = null,
        actions: []const Action(E, S, A),
    };
}

pub fn Fsm(comptime E: type, comptime S: type, comptime A: type) type {
    return struct {
        const Self = @This();
        state: S,
        transitions: []const Transition(E, S, A),

        pub fn input(self: *Self, event: E) ?A {
            find_state: for (self.transitions) |transition| {
                if (transition.state) |state| {
                    if (self.state != state) {
                        continue :find_state;
                    }
                }
                find_action: for (transition.actions) |action| {
                    if (action.event) |e| {
                        if (e != event) {
                            continue :find_action;
                        }
                    }
                    if (action.new_state) |new_state| {
                        self.state = new_state;
                    }
                    return action.action;
                }
            }
            return null;
        }
    };
}
