const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .shape_use_32bit_indices = b.option(
            bool,
            "shape_use_32bit_indices",
            "Enable par shapes 32-bit indices",
        ) orelse true,
        .shared = b.option(
            bool,
            "shared",
            "Build as shared library",
        ) orelse false,
        .gltfpack = b.option(
            bool,
            "gltfpack",
            "Build gltfpack executable",
        ) orelse false,
        .gltfpack_basisu = b.option(
            bool,
            "gltfpack_basisu",
            "Build gltfpack executable with basisu support",
        ) orelse false,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }

    const options_module = options_step.createModule();
    const zmesh_module = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zmesh_options", .module = options_module },
        },
    });

    const zmesh_lib = b.addLibrary(.{
        .name = "zmesh",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    if (options.shared and target.result.os.tag == .windows) {
        zmesh_lib.root_module.addCMacro("PAR_SHAPES_API", "__declspec(dllexport)");
        zmesh_lib.root_module.addCMacro("CGLTF_API", "__declspec(dllexport)");
        zmesh_lib.root_module.addCMacro("MESHOPTIMIZER_API", "__declspec(dllexport)");
        zmesh_lib.root_module.addCMacro("ZMESH_API", "__declspec(dllexport)");
    }

    b.installArtifact(zmesh_lib);

    zmesh_lib.root_module.link_libcpp = true;
    if (target.result.abi != .msvc)
        zmesh_lib.root_module.link_libcpp = true;

    const par_shapes_t = if (options.shape_use_32bit_indices)
        "-DPAR_SHAPES_T=uint32_t"
    else
        "-DPAR_SHAPES_T=uint16_t";

    zmesh_lib.root_module.addIncludePath(b.path("libs/par_shapes"));
    zmesh_lib.root_module.addCSourceFile(.{
        .file = b.path("libs/par_shapes/par_shapes.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined", par_shapes_t },
    });

    zmesh_lib.root_module.addIncludePath(b.path("libs/cgltf"));
    zmesh_lib.root_module.addCSourceFile(.{
        .file = b.path("libs/cgltf/cgltf.c"),
        .flags = &.{"-std=c99"},
    });

    // Meshopt is built as a static library so it can link to gltfpack and zmesh separtely
    // Don't want to drag all of zmesh direct in to gltfpack
    const meshopt = b.dependency("meshoptimizer", .{});
    const meshopt_lib = b.addLibrary(.{
        .name = "meshopt_lib",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    meshopt_lib.root_module.addCSourceFiles(.{
        .root = meshopt.path(""),
        .files = &.{
            "src/allocator.cpp",
            "src/clusterizer.cpp",
            "src/indexanalyzer.cpp",
            "src/indexgenerator.cpp",
            "src/indexcodec.cpp",
            "src/meshletcodec.cpp",
            "src/meshletutils.cpp",
            "src/opacitymap.cpp",
            "src/overdrawoptimizer.cpp",
            "src/partition.cpp",
            "src/quantization.cpp",
            "src/rasterizer.cpp",
            "src/simplifier.cpp",
            "src/spatialorder.cpp",
            "src/stripifier.cpp",
            "src/tangentspace.cpp",
            "src/vcacheoptimizer.cpp",
            "src/vertexcodec.cpp",
            "src/vertexfilter.cpp",
            "src/vfetchoptimizer.cpp",
        },
        .flags = &.{""},
    });
    meshopt_lib.root_module.addIncludePath(meshopt.path("src"));

    zmesh_lib.root_module.linkLibrary(meshopt_lib);

    if (options.gltfpack or options.gltfpack_basisu) {
        const gltfpack_exe = b.addExecutable(.{
            .name = "gltfpack",
            .win32_manifest = meshopt.path("gltf/gltfpack.manifest"),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .link_libcpp = true,
            }),
        });

        const flags: []const []const u8 = blk: {
            if (options.gltfpack_basisu) {
                break :blk &.{"-DWITH_BASISU"};
            } else {
                break :blk &.{""};
            }
        };

        gltfpack_exe.root_module.addCSourceFiles(.{
            .root = meshopt.path(""),
            .files = &.{
                "gltf/animation.cpp",
                "gltf/encodebasis.cpp",
                "gltf/encodewebp.cpp",
                "gltf/fileio.cpp",
                "gltf/gltfpack.cpp",
                "gltf/image.cpp",
                "gltf/json.cpp",
                "gltf/material.cpp",
                "gltf/mesh.cpp",
                "gltf/node.cpp",
                "gltf/parsegltf.cpp",
                "gltf/parselib.cpp",
                "gltf/parseobj.cpp",
                "gltf/stream.cpp",
                "gltf/wasistubs.cpp",
                "gltf/write.cpp",
            },
            .flags = flags,
            .language = .cpp,
        });

        if (options.gltfpack_basisu) {
            const basisu = b.dependency("basisu", .{});
            const basisu_lib = b.addLibrary(.{
                .name = "basisu_lib",
                .linkage = .static,
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .link_libcpp = true,
                }),
            });

            basisu_lib.root_module.addCSourceFiles(.{
                .root = basisu.path(""),
                .files = &.{
                    "encoder/basisu_backend.cpp",
                    "encoder/basisu_basis_file.cpp",
                    "encoder/basisu_comp.cpp",
                    "encoder/basisu_enc.cpp",
                    "encoder/basisu_etc.cpp",
                    "encoder/basisu_frontend.cpp",
                    "encoder/basisu_gpu_texture.cpp",
                    "encoder/basisu_pvrtc1_4.cpp",
                    "encoder/basisu_resampler.cpp",
                    "encoder/basisu_resample_filters.cpp",
                    "encoder/basisu_ssim.cpp",
                    "encoder/basisu_uastc_enc.cpp",
                    "encoder/basisu_bc7enc.cpp",
                    "encoder/jpgd.cpp",
                    "encoder/basisu_kernels_sse.cpp",
                    "encoder/basisu_opencl.cpp",
                    "encoder/pvpngreader.cpp",
                    "encoder/basisu_uastc_hdr_4x4_enc.cpp",
                    "encoder/basisu_astc_hdr_6x6_enc.cpp",
                    "encoder/basisu_astc_hdr_common.cpp",
                    "encoder/basisu_astc_ldr_common.cpp",
                    "encoder/basisu_astc_ldr_encode.cpp",
                    "encoder/basisu_tinyexr.cpp",
                    "encoder/3rdparty/android_astc_decomp.cpp",
                    "transcoder/basisu_transcoder.cpp",
                    "zstd/zstd.c",
                },
                .flags = &.{ "-DBASISD_SUPPORT_KTX2_ZSTD=1", "-DBASISU_DISABLE_ANDROID_ASTC_DECOMP=0" },
            });
            basisu_lib.root_module.addIncludePath(basisu.path("encoder"));
            basisu_lib.root_module.addIncludePath(basisu.path("transcoder"));

            gltfpack_exe.root_module.addIncludePath(basisu.path(""));
            gltfpack_exe.root_module.linkLibrary(basisu_lib);
        }

        gltfpack_exe.root_module.linkLibrary(meshopt_lib);

        b.installArtifact(gltfpack_exe);

        const expose_bin = b.addNamedWriteFiles("gltfpack_bin");
        _ = expose_bin.addCopyDirectory(b.path("zig-out/bin"), "", .{});
    }

    const test_step = b.step("test", "Run zmesh tests");

    const tests = b.addTest(.{
        .name = "zmesh-tests",
        .root_module = zmesh_module,
    });
    b.installArtifact(tests);

    tests.root_module.linkLibrary(zmesh_lib);
    tests.root_module.addIncludePath(b.path("libs/cgltf"));

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
