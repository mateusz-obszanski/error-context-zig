// Based on some long blog post that does not work. Anyway, the general idea is
// interesting.
// https://gencmurat.com/en/posts/advanced-guide-to-return-values-and-error-unions-in-zig/

const std = @import("std");
const fmt = std.fmt;
const comptimePrint = fmt.comptimePrint;

/// Wrapper for error values, provides additional context of specified type.
pub fn ErrorContext(comptime ErrorSet: type, comptime ContextType: type) type {
    const compilation_err_format =
        "Expected an error set (like error{ A, B }), got {any}.";

    switch (@typeInfo(ErrorSet)) {
        .ErrorSet => {},
        else => switch (@typeInfo(ContextType)) {
            .ErrorSet => @compileError(
                comptimePrint(
                    compilation_err_format ++
                        "\nHint: You probably swapped Errors and ContextType.",
                    .{ErrorSet},
                ),
            ),
            else => @compileError(comptimePrint(
                compilation_err_format,
                .{ErrorSet},
            )),
        },
    }

    return struct {
        err: ErrorSet,
        context: ContextType,

        const Self = @This();

        pub const generic_parameters: struct {
            Err: type = ErrorSet,
            Context: type = ContextType,
        } = .{};

        /// Create a new instance.
        pub fn init(err: ErrorSet, context: ContextType) Self {
            return Self{ .err = err, .context = context };
        }

        /// Raise the wrapped error.
        pub fn raise(self: Self) ErrorSet!void {
            return self.err;
        }

        /// Convert to tuple.
        pub fn asTuple(self: Self) struct { ErrorSet, ContextType } {
            return .{ self.err, self.context };
        }
    };
}

const testing = std.testing;
const expectError = testing.expectError;

test ErrorContext {
    const expected_err = error.Bzzz;

    const riskyOperation = struct {
        fn riskyOperation() ErrorContext(error{Bzzz}, []const u8) {
            return ErrorContext(error{Bzzz}, []const u8).init(
                expected_err,
                "Failed during critical step",
            );
        }
    }.riskyOperation;

    try expectError(expected_err, riskyOperation().raise());
}

const Str = []const u8;
const NotErrorContextReason = Str;

fn _checkErrorContext(comptime T: type) ?NotErrorContextReason {
    const compile_error_prefix = "Expected ErrorContext, provided type ";

    // assumes that T is a struct
    const checkField = struct {
        pub fn checkField(name: []const u8) ?NotErrorContextReason {
            if (!@hasField(T, name)) return comptimePrint(
                compile_error_prefix ++ "has no field '{s}' - got {any}",
                .{ name, T },
            );
            return null;
        }
    }.checkField;

    const checkMethod = struct {
        pub fn checkMethod(name: []const u8, signature: type) ?NotErrorContextReason {
            if (!@hasDecl(T, name)) return comptimePrint(
                compile_error_prefix ++ "has no method '{s}' - got {any}",
                .{ name, T },
            );

            const method_signature = @TypeOf(@field(T, name));

            if (method_signature != signature) return comptimePrint(
                compile_error_prefix ++
                    "has wrong member function signature for {s} - expected " ++
                    "{any}, got {any}, provided type was {any}",
                .{ name, signature, method_signature, T },
            );
            return null;
        }
    }.checkMethod;

    const info = @typeInfo(T);

    if (info != .Struct) return comptimePrint(
        compile_error_prefix ++ "is not a struct - got {any}",
        .{T},
    );

    if (checkField("err")) |reason| {
        return reason;
    }
    if (checkField("context")) |reason| {
        return reason;
    }

    const ErrorSet = info.Struct.fields[0].type;
    const ContextType = info.Struct.fields[1].type;

    if (checkMethod("init", fn (ErrorSet, ContextType) T)) |reason| {
        return reason;
    }
    if (checkMethod("raise", fn (T) ErrorSet!void)) |reason| {
        return reason;
    }

    return null;
}

/// Ensure a type is a specialization of `ErrorContext`, raise a compilation
/// error otherwise.
pub fn ensureErrorContext(comptime T: type) void {
    if (_checkErrorContext(T)) |reason| {
        @compileError(reason);
    }
}

/// Check whether a type is a specialization of `ErrorContext`.
pub fn isErrorContext(comptime T: type) void {
    return _checkErrorContext(T) == null;
}

/// Create an `ErrorContext` from an error union, like `error{MyErr}!i32`.
pub fn FromErrorUnion(comptime ErrorUnion: type) type {
    const ErrorSet, const Type = switch (@typeInfo(ErrorUnion)) {
        .ErrorUnion => |ErrUn| .{ ErrUn.error_set, ErrUn.payload },
        else => @compileError(comptimePrint(
            "Expected an error union (like !i32), got {any}",
            .{ErrorUnion},
        )),
    };
    return ErrorContext(ErrorSet, Type);
}

test FromErrorUnion {
    _ = FromErrorUnion(error{Dupa}!i32);
}

/// Create an `ErrorContext` that accepts any error as its error value.
pub fn Any(comptime ContextType: type) type {
    return ErrorContext(anyerror, ContextType);
}

test Any {
    const expected_err = error.Bzzz;

    const riskyOperation = struct {
        fn riskyOperation() Any([]const u8) {
            return Any([]const u8).init(
                expected_err,
                "Failed during critical step",
            );
        }
    }.riskyOperation;

    try expectError(expected_err, riskyOperation().raise());
}

/// Result tagged union.
pub const ResultContext = struct {
    pub fn Result(comptime Ok: type, comptime ErrContext: type) type {
        ensureErrorContext(ErrContext);

        const generics = ErrContext.generic_parameters;
        const Err: type = generics.Err;
        const Context: type = generics.Context;

        return union(enum) {
            ok: Ok,
            err: ErrContext,

            const Self = @This();

            /// Initialize an 'Ok' variant.
            pub fn initOk(value: Ok) Self {
                return Self{ .ok = value };
            }

            /// Initialize an error with context variant.
            pub fn initErr(value: ErrContext) Self {
                return Self{ .err = value };
            }

            /// Initialize an error with context variant.
            pub fn initErr2(err_: Err, context: Context) Self {
                return Self.initErr(ErrorContext(Err, Context).init(err_, context));
            }

            pub fn isOk(self: Self) bool {
                return switch (self) {
                    .ok => true,
                    else => false,
                };
            }

            pub fn isErr(self: Self) bool {
                return switch (self) {
                    .err => true,
                    else => false,
                };
            }

            /// Return the 'Ok' variant, otherwise unreachable.
            pub fn assumeOk(self: Self) Ok {
                return switch (self) {
                    .ok => |value| value,
                    else => unreachable,
                };
            }

            /// Return the error variant, otherwise unreachable.
            pub fn assumeErr(self: Self) ErrContext {
                return switch (self) {
                    .err => |e| e,
                    else => unreachable,
                };
            }

            /// Return an error union, discard the context in case of error.
            pub fn raiseStripContext(self: Self) Err!Ok {
                return switch (self) {
                    .err => |context| context.err,
                    else => self,
                };
            }

            pub fn raiseAssumeErr(self: Self) Err!void {
                _ = try self.raiseStripContext();
            }
        };
    }
};

const expectEqual = testing.expectEqual;

test ResultContext {
    const Result = ResultContext.Result(
        i32,
        ErrorContext(error{Bzzz}, []const u8),
    );

    try expectEqual(42, Result.initOk(42).assumeOk());
    try expectError(
        error.Bzzz,
        Result.initErr2(error.Bzzz, "some context").assumeErr().raise(),
    );
}

const refAllDecls = testing.refAllDecls;

test {
    refAllDecls(@This());
}
