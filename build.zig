const std = @import("std");
const generate = @import("generate.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const lib_raylib = raylib_dep.artifact("raylib");

    var baseBuf: [2048]u8 = undefined;
    const raylib_base_dir = std.fmt.bufPrint(&baseBuf, "{s}/{s}", .{ lib_raylib.include_dirs.items[0].path.path, "../../../.." }) catch unreachable;

    var printBuf: [2048]u8 = undefined;

    //--- parse raylib and generate JSONs for all signatures --------------------------------------
    const jsons = b.step("parse", "parse raylib headers and generate raylib jsons");

    const raylib_parser_build = b.addExecutable(.{
        .name = "raylib_parser",
        .root_source_file = std.build.FileSource.relative("raylib_parser.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    raylib_parser_build.addCSourceFile(.{ .file = .{ .path = std.fmt.bufPrint(&printBuf, "{s}/{s}", .{ raylib_base_dir, "parser/raylib_parser.c" }) catch unreachable }, .flags = &.{} });
    raylib_parser_build.linkLibC();

    //raylib
    const raylib_H = b.addRunArtifact(raylib_parser_build);
    raylib_H.addArgs(&.{
        "-i", std.fmt.bufPrint(&printBuf, "{s}/{s}", .{ raylib_base_dir, "src/raylib.h" }) catch unreachable,
        "-o", "raylib.json",
        "-f", "JSON",
        "-d", "RLAPI",
    });
    jsons.dependOn(&raylib_H.step);

    //raymath
    const raymath_H = b.addRunArtifact(raylib_parser_build);
    raymath_H.addArgs(&.{
        "-i", std.fmt.bufPrint(&printBuf, "{s}/{s}", .{ raylib_base_dir, "src/raymath.h" }) catch unreachable,
        "-o", "raymath.json",
        "-f", "JSON",
        "-d", "RMAPI",
    });
    jsons.dependOn(&raymath_H.step);

    //rlgl
    const rlgl_H = b.addRunArtifact(raylib_parser_build);
    rlgl_H.addArgs(&.{
        "-i", std.fmt.bufPrint(&printBuf, "{s}/{s}", .{ raylib_base_dir, "src/rlgl.h" }) catch unreachable,
        "-o", "rlgl.json",
        "-f", "JSON",
        "-d", "RLAPI",
    });
    jsons.dependOn(&rlgl_H.step);

    //--- Generate intermediate -------------------------------------------------------------------
    const intermediate = b.step("intermediate", "generate intermediate representation of the results from 'zig build parse' (keep custom=true)");
    var intermediateZigStep = b.addRunArtifact(b.addExecutable(.{
        .name = "intermediate",
        .root_source_file = std.build.FileSource.relative("intermediate.zig"),
        .target = target,
    }));
    intermediate.dependOn(&intermediateZigStep.step);

    //--- Generate bindings -----------------------------------------------------------------------
    const bindings = b.step("bindings", "generate bindings in from bindings.json");
    var generateZigStep = b.addRunArtifact(b.addExecutable(.{
        .name = "generate",
        .root_source_file = std.build.FileSource.relative("generate.zig"),
        .target = target,
    }));
    const fmt = b.addFmt(.{ .paths = &.{generate.outputFile} });
    fmt.step.dependOn(&generateZigStep.step);
    bindings.dependOn(&fmt.step);

    //--- just build raylib_parser.exe ------------------------------------------------------------
    const raylib_parser_install = b.step("raylib_parser", "build ./zig-out/bin/raylib_parser.exe");
    const generateBindings_install = b.addInstallArtifact(raylib_parser_build, .{});
    raylib_parser_install.dependOn(&generateBindings_install.step);

    const lib = b.addStaticLibrary(.{ .name = "raylib-zig", .target = target, .optimize = optimize });
    for (lib_raylib.include_dirs.items) |item| lib.addIncludePath(item.path);
    for (lib_raylib.lib_paths.items) |item| lib.addLibraryPath(item);
    lib.linkLibC();
    lib.linkLibrary(lib_raylib);
    lib.addCSourceFile(.{ .file = .{ .path = "./marshal.c" }, .flags = &.{} });
    lib.addIncludePath(.{ .path = "." });
    b.installArtifact(lib);
    b.installArtifact(lib_raylib);

    _ = b.addModule("raylib", .{ .source_file = .{ .path = "./raylib.zig" } });
}

// // above: generate library
// // below: linking (use as dependency)

// fn current_file() []const u8 {
//     return @src().file;
// }

// const cwd = std.fs.path.dirname(current_file()).?;
// const sep = std.fs.path.sep_str;
// const dir_raylib = cwd ++ sep ++ "raylib";
// const dir_raylib_src = cwd ++ sep ++ "raylib/src";

// fn linkThisLibrary(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.build.LibExeObjStep {
//     const lib = b.addStaticLibrary(.{ .name = "raylib-zig", .target = target, .optimize = optimize });
//     lib.addIncludePath(.{ .path = dir_raylib_src });
//     lib.addIncludePath(.{ .path = cwd });
//     lib.linkLibC();
//     lib.addCSourceFile(.{ .file = .{ .path = cwd ++ sep ++ "marshal.c" }, .flags = &.{} });
//     return lib;
// }

// /// add this package to exe
// pub fn addTo(b: *std.Build, exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, optimize: std.builtin.Mode) void {
//     const raylib_build = @import("./raylib/src/build.zig");

//     exe.addAnonymousModule("raylib", .{ .source_file = .{ .path = cwd ++ sep ++ "raylib.zig" } });
//     exe.addIncludePath(.{ .path = dir_raylib_src });
//     exe.addIncludePath(.{ .path = cwd });
//     const lib = linkThisLibrary(b, target, optimize);
//     const lib_raylib = raylib_build.addRaylib(b, target, optimize, .{});
//     exe.linkLibrary(lib_raylib);
//     exe.linkLibrary(lib);
// }
