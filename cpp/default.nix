{ meta, proto_lib }: rec {
  toCMakeDependencies = x: proto_lib.strings.concatMapStringsSep ";" (dep: dep.name + "_proto_cpp") x;
  toBuildDepsCpp = x: pkgs: proto_lib.lists.forEach x (a: pkgs.${a.name + "_proto_cpp"});
  toProtoDepsCMake = x: proto_lib.strings.concatMapStringsSep ";" (a: a.src) x;
  grpcCmake = (builtins.readFile ./CMakeLists.txt.grpc);
  protobufCmake = (builtins.readFile ./CMakeLists.txt.protobuf);
  protobufCmakeConfig = (builtins.readFile ./protoConfig.cmake.in);
  grpcCmakeConfig = (builtins.readFile ./grpcConfig.cmake.in);
  protoDeps = proto_lib.recursiveProtoDeps meta.protoDeps;

  utilCMake = (builtins.readFile ./util.cmake);
  relativeProto = (proto_lib.strings.concatMapStringsSep ";" (a: proto_lib.strings.removePrefix (meta.src + "/") a) (builtins.filter (a: proto_lib.hasSuffix ".proto" a) (proto_lib.filesystem.listFilesRecursive meta.src)));

  package_protobuf = { stdenv, cmake, protobuf, lld, pkgs }: stdenv.mkDerivation rec {
    name = meta.name + "_proto_cpp";
    src = meta.src;
    version = meta.version;
    propagatedBuildInputs = [ protobuf ] ++ (toBuildDepsCpp meta.protoDeps pkgs);
    nativeBuildInputs = [ cmake protobuf lld ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DCPP_NAME=${name}"
      "-DCPP_VERSION=${version}"
      "-DPROTOS=${relativeProto}"
      "-DPROTO_DEPS=${(toProtoDepsCMake ((protoDeps) ++ [meta]))}"
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
    outputs = [ "out" "dev" ];
    separateDebugInfo = true;
  };

  package_grpc = { stdenv, cmake, protobuf, grpc, pkgconfig, openssl, zlib, c-ares, pkgs }: stdenv.mkDerivation rec {
    name = meta.name + "_grpc_cpp";
    src = meta.src;
    version = meta.version;
    propagatedBuildInputs = [ protobuf grpc openssl ] ++ (toBuildDepsCpp (meta.protoDeps ++ [ meta ]) pkgs);
    nativeBuildInputs = [ cmake protobuf ];
    propagatedNativeBuildInputs = [ pkgconfig ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DCPP_NAME=${name}"
      "-DCPP_VERSION=${version}"
      "-DPROTOS=${relativeProto}"
      "-DPROTO_DEPS=${(toProtoDepsCMake (protoDeps ++ [meta]))}"
      "-DCPP_DEPS=${toCMakeDependencies (meta.protoDeps ++ [meta])}"
    ];
    cmakeFile = pkgs.writeText "CMakeLists.txt" grpcCmake;
    cmakeFileConfig = pkgs.writeText "${name}Config.cmake.in" grpcCmakeConfig;
    utilCMakeFile = pkgs.writeText "util.cmake" utilCMake;
    prePatch = ''
      cp $cmakeFile CMakeLists.txt
      cp $cmakeFileConfig ${name}Config.cmake.in
      cp $utilCMakeFile util.cmake
    '';
    outputs = [ "out" "dev" ];
    separateDebugInfo = true;
  };
}
