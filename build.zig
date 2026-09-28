const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Prebuilt static library (drop-in: original STBIDEF API, AVX2 runtime dispatch).
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addIncludePath(b.path("src"));
    lib_mod.addCSourceFile(.{ .file = b.path("lib/stb_image.c"), .flags = &.{} });
    const lib = b.addLibrary(.{
        .name = "stb-image-opt",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);
    b.installFile("src/stb_image.h", "include/stb_image.h");

    // decode_dump harness tool.
    const dd_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dd_mod.addIncludePath(b.path("src"));
    dd_mod.addCSourceFile(.{ .file = b.path("tools/decode_dump.c"), .flags = &.{} });
    // libm is separate only on glibc/musl Linux; macOS folds it into libSystem
    // and Windows into the CRT, where linking -lm would fail.
    if (target.result.os.tag == .linux) dd_mod.linkSystemLibrary("m", .{});
    const dd = b.addExecutable(.{
        .name = "decode_dump",
        .root_module = dd_mod,
    });
    b.installArtifact(dd);
}
