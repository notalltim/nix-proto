{ lib }: rec {
  inherit (lib.strings) concatMapStringsSep removePrefix hasSuffix;
  inherit (lib.lists) forEach;
  inherit (lib.filesystem) listFilesRecursive;
  inherit (builtins) readFile filter;
  inherit (lib) recursiveProtoDeps optionals;

  toCMakeDependencies = x: concatMapStringsSep ";" (dep: dep.name + "_proto_cpp") x;
  toBuildDepsCpp = x: pkgs: forEach x (a: pkgs.${a.name + "_proto_cpp"});
  toProtoDepsCMake = x: concatMapStringsSep ";" (a: a.src) x;
  grpcCmake = (readFile ./CMakeLists.txt.grpc);
  protobufCmake = (readFile ./CMakeLists.txt.protobuf);
  protobufCmakeConfig = (readFile ./protoConfig.cmake.in);
  grpcCmakeConfig = (readFile ./grpcConfig.cmake.in);

  utilCMake = (readFile ./util.cmake);

  gen_protobuf = { stdenv, cmake, protobuf, pkgs, __proto_internal_meta_package}: stdenv.mkDerivation rec {
    meta = (lib.loadMeta __proto_internal_meta_package);
    name = meta.name + "_proto_cpp";
    src = meta.src;
    version = meta.version;
    propagatedBuildInputs = [ protobuf ] ++ (toBuildDepsCpp meta.protoDeps pkgs);
    nativeBuildInputs = [ cmake protobuf ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DCPP_NAME=${name}"
      "-DCPP_VERSION=${version}"
      "-DPROTOS=${(concatMapStringsSep ";" (a: removePrefix (meta.src + "/") a) (filter (a: hasSuffix ".proto" a) (listFilesRecursive meta.src)))}"
      "-DCPP_DEPS=${toCMakeDependencies meta.protoDeps}"
    ];
    cmakeFile = pkgs.writeText "CMakeLists.txt" protobufCmake;
    cmakeFileConfig = pkgs.writeText "${name}Config.cmake.in" protobufCmakeConfig;
    utilCMakeFile = pkgs.writeText "util.cmake" utilCMake;
    prePatch = ''
      cp $cmakeFile CMakeLists.txt
      cp $cmakeFileConfig ${name}Config.cmake.in
      cp $utilCMakeFile util.cmake
    '';
    preConfigure = ''
      cmakeFlags="-DPROTO_DEPS=${(toProtoDepsCMake ((recursiveProtoDeps meta.protoDeps) ++ [meta]))};$PWD $cmakeFlags"
    '';
    outputs = [ "out" "dev" ];
    separateDebugInfo = !stdenv.hostPlatform.isStatic;
  };

  gen_grpc = { stdenv, cmake, protobuf, grpc, pkg-config, openssl, pkgs, __proto_internal_meta_package }: stdenv.mkDerivation rec {
    meta = (lib.loadMeta __proto_internal_meta_package);
    name = meta.name + "_grpc_cpp";
    src = meta.src;
    version = meta.version;
    propagatedBuildInputs = [ protobuf grpc openssl ] ++ (toBuildDepsCpp (meta.protoDeps ++ [ meta ]) pkgs);
    nativeBuildInputs = [ cmake protobuf ];
    propagatedNativeBuildInputs = [ pkg-config ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DCPP_NAME=${name}"
      "-DCPP_VERSION=${version}"
      "-DPROTOS=${(concatMapStringsSep ";" (a: removePrefix (meta.src + "/") a) (filter (a: hasSuffix ".proto" a) (listFilesRecursive meta.src)))}"
      "-DCPP_DEPS=${toCMakeDependencies (meta.protoDeps ++ [meta])}"
    ] ++ optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "-DCMAKE_CROSSCOMPILING=OFF" # Needed due to GRPC relying on the CMAKE_CROSSCOMPILING for adding the plugin targets
    ];
    cmakeFile = pkgs.writeText "CMakeLists.txt" grpcCmake;
    cmakeFileConfig = pkgs.writeText "${name}Config.cmake.in" grpcCmakeConfig;
    utilCMakeFile = pkgs.writeText "util.cmake" utilCMake;
    prePatch = ''
      cp $cmakeFile CMakeLists.txt
      cp $cmakeFileConfig ${name}Config.cmake.in
      cp $utilCMakeFile util.cmake
    '';
    preConfigure = ''
      cmakeFlags="-DPROTO_DEPS=${(toProtoDepsCMake (recursiveProtoDeps meta.protoDeps))};$PWD $cmakeFlags"
    '';
    outputs = [ "out" "dev" ];
    separateDebugInfo = !stdenv.hostPlatform.isStatic;
  };
}
