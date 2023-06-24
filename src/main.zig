const std = @import("std");

const Mode = enum {
    Interpretation,
    Compilation,
};

const TokenType = enum {
    PUSH,
    POP,
    ADD,
    SUB,
    MUL,
    WORD_DEFINITION,
    WORD_NAME,
    WORD_END,
    CALL_WORD,
};

const Token = struct {
    type: TokenType,
    value: i64,

    const Self = @This();

    pub fn init(a: std.mem.Allocator) !*Token {
        return try a.create(Token);
    }

    pub fn deinit(self: *Self, a: std.mem.Allocator) void {
        a.destroy(self);
    }
};

const Word = struct {
    name: std.ArrayList(u8),
    definition: std.ArrayList(*Token),

    const Self = @This();

    pub fn init(a: std.mem.Allocator) !*Self {
        return try a.create(Word);
    }

    pub fn set(self: *Self, a: std.mem.Allocator, name: []const u8) !void {
        self.name = std.ArrayList(u8).init(a);
        try self.name.writer().writeAll(name);
        self.definition = std.ArrayList(*Token).init(a);
    }

    pub fn deinit(self: *Self, a: std.mem.Allocator) void {
        self.name.deinit();
        for (self.definition.items) |i| {
            i.deinit(a);
        }
        self.definition.deinit();
    }

    pub fn add_definition(self: *Self, token: *Token, a: std.mem.Allocator) !void {
        var t = try Token.init(a);
        t.* = Token{
            .type = token.type,
            .value = token.value,
        };
        try self.definition.append(t);
    }
};

const STACK_SIZE = 100;

const Stack = struct {
    arr: [STACK_SIZE]i64,
    pointer: u8,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .arr = [_]i64{0} ** STACK_SIZE,
            .pointer = 0,
        };
    }

    pub fn push(self: *Self, number: i64) !void {
        if (self.pointer >= STACK_SIZE) {
            return error.RuntimeError;
        } else {
            self.arr[self.pointer] = number;
            self.pointer += 1;
        }
    }

    pub fn pop(self: *Self) !i64 {
        if (self.pointer <= 0) {
            return error.RuntimeError;
        } else {
            self.pointer -= 1;
            var r = self.arr[self.pointer];

            return r;
        }
    }

    pub fn print(self: *Self, out_stream: anytype) !void {
        var p = self.pointer;

        while (true) {
            if (p <= 0) {
                break;
            } else {
                p -= 1;
                try out_stream.print("{}, ", .{self.arr[p]});
            }
        }
    }
};

const VM = struct {
    mode: Mode,
    stack: Stack,
    wordlist: std.StringHashMap(*Word),

    const Self = @This();

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .mode = Mode.Interpretation,
            .stack = Stack.init(),
            .wordlist = std.StringHashMap(*Word).init(a),
        };
    }

    pub fn deinit(self: *Self) void {
        self.wordlist.clearAndFree();
        self.wordlist.deinit();
    }

    pub fn add_word(self: *Self, name: []const u8, word: *Word) !void {
        try self.wordlist.put(name, word);
    }

    pub fn search_word(self: *Self, name: []const u8) !?*Word {
        if (self.wordlist.get(name)) |word| {
            return word;
        } else {
            return error.RuntimeError;
        }
    }

    pub fn push(self: *Self, number: i64) !void {
        try self.stack.push(number);
    }

    pub fn pop(self: *Self) !void {
        _ = try self.stack.pop();
    }

    pub fn add(self: *Self) !void {
        var second_value = try self.stack.pop();
        var first_value = try self.stack.pop();

        var result = first_value + second_value;

        try self.stack.push(result);
    }

    pub fn sub(self: *Self) !void {
        var second_value = try self.stack.pop();
        var first_value = try self.stack.pop();

        var result = first_value - second_value;

        try self.stack.push(result);
    }

    pub fn mul(self: *Self) !void {
        var second_value = try self.stack.pop();
        var first_value = try self.stack.pop();

        var result = first_value * second_value;

        try self.stack.push(result);
    }

    pub fn exec(self: *Self, token: *Token) !void {
        switch (token.type) {
            TokenType.PUSH => {
                try self.push(token.value);
            },
            TokenType.POP => {
                try self.pop();
            },
            TokenType.ADD => {
                try self.add();
            },
            TokenType.SUB => {
                try self.sub();
            },
            TokenType.MUL => {
                try self.mul();
            },
            else => {
                //try stdout.print("error!", .{});
            },
        }
    }
};

pub fn eval(vm: *VM, token: *Token, word_buf: ?*Word, stdout: anytype, a: std.mem.Allocator) !void {
    if (vm.mode == Mode.Compilation) {
        try stdout.print("# {}\n", .{token.type});
        try word_buf.?.add_definition(token, a);
    } else {
        try stdout.print("{}\n", .{token.type});
        try vm.exec(token);
    }
}

pub fn run(vm: *VM, in_stream: anytype, stdout: anytype, a: std.mem.Allocator) !void {
    var buf: [100]u8 = undefined;
    var word_buf: ?*Word = null;
    var get_name: i64 = 0;

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var tokens = std.mem.split(u8, line, " ");
        while (tokens.next()) |t| {
            var tt = t;
            var token = try Token.init(a);
            defer token.deinit(a);

            if (std.fmt.parseInt(i64, t, 10)) |number| {
                token.* = Token{
                    .type = TokenType.PUSH,
                    .value = number,
                };
            } else |_| {
                if (std.mem.eql(u8, tt, "+")) {
                    token.* = Token{
                        .type = TokenType.ADD,
                        .value = 0,
                    };
                } else if (std.mem.eql(u8, tt, "-")) {
                    token.* = Token{
                        .type = TokenType.SUB,
                        .value = 0,
                    };
                } else if (std.mem.eql(u8, tt, "*")) {
                    token.* = Token{
                        .type = TokenType.MUL,
                        .value = 0,
                    };
                } else if (std.mem.eql(u8, tt, ":")) {
                    get_name = 1;
                    token.* = Token{
                        .type = TokenType.WORD_DEFINITION,
                        .value = 0,
                    };
                } else if (std.mem.eql(u8, tt, ";")) {
                    if (word_buf == null) {
                        try stdout.print("Word Definition Error!\n", .{});
                        break;
                    }
                    try vm.add_word(word_buf.?.*.name.items, word_buf.?);
                    vm.mode = Mode.Interpretation;
                    token.* = Token{
                        .type = TokenType.WORD_END,
                        .value = 0,
                    };
                } else {
                    if (get_name == 1) {
                        word_buf = try Word.init(a);
                        try word_buf.?.set(a, tt);
                        vm.mode = Mode.Compilation;
                        token.* = Token{
                            .type = TokenType.WORD_NAME,
                            .value = 0,
                        };
                        get_name = 0;
                    } else if (try vm.search_word(tt)) |word| {
                        for (word.definition.items) |d| {
                            try eval(vm, d, word_buf, stdout, a);
                        }
                        token.* = Token{
                            .type = TokenType.CALL_WORD,
                            .value = 0,
                        };
                    } else {
                        try stdout.print("Syntax Error!\n", .{});
                    }
                }
            }
            try eval(vm, token, word_buf, stdout, a);
        }
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const a = std.heap.page_allocator;

    var vm = VM.init(a);
    defer vm.deinit();

    var fp = try std.fs.cwd().openFile("test.txt", .{});
    defer fp.close();

    var buf_reader = std.io.bufferedReader(fp.reader());
    var in_stream = buf_reader.reader();

    try run(&vm, in_stream, stdout, a);

    try vm.stack.print(stdout);
}
