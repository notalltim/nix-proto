{ lib }:
rec {
  inherit (lib.strings) concatMapStringsSep removePrefix hasSuffix;
  inherit (lib.lists) forEach;
  inherit (lib.filesystem) listFilesRecursive;
  inherit (builtins) readFile filter;
  inherit (lib) recursiveProtoDeps optionals loadMeta;

  /*
    *
    Create a string that represents a list of library names in CMake from a list of metadata attribute sets that at minimum provide the name.

    # Example

    ```nix
    toCMakeDependencies [{name = "test"; ... } {name = "test2"} ] => "test_proto_cpp;test2_proto_cpp"
    ```

    # Type

    ```
    toCMakeDependencies :: List -> String
    ```

    - [deps] A list of attribute sets containing at minimum the name of the base proto.

    - [returns] A string of semicolon separated names + suffix
  */
  toCMakeDependencies = deps: concatMapStringsSep ";" (dep: dep.name + "_proto_cpp") deps;

  /*
    *
    Create a list of derivations from a package set and a list of metadata attribute sets that at minimum provide the name.

    # Example

    ```nix
    toBuildDepsCpp [{name = "test"; ... } {name = "test2"} ] pkgs => [pkgs.test_proto_cpp pkgs.test2_proto_cpp]
    ```

    # Type

    ```
    toBuildDepsCpp :: List -> List
    ```

    - [deps] A list of attribute sets containing at minimum the name of the base proto.
    - [pkgs] the pkg set that the derivation is being built into.

    - [returns] A list of derivations from the package set.
  */
  toBuildDepsCpp = deps: pkgs: forEach deps (dep: pkgs.${dep.name + "_proto_cpp"});

  /*
    *
    Create a string that represents a list of proto include locations in CMake from a list of metadata attribute sets that at minimum provide the source location.

    # Example

    ```nix
    toProtoDepsCMake [{src = "/store/path; ... } {name = "/store/path2"} ] => "/store/path;/store/path2"
    ```

    # Type

    ```
    toProtoDepsCMake :: List -> String
    ```

    - [deps] A list of attribute sets containing at minimum the src location of the base proto.

    - [returns] A string of semicolon separated of paths to protos
  */
  toProtoDepsCMake = deps: concatMapStringsSep ";" (dep: dep.src) deps;

  /*
    *
    Create a string that represents a list of relative paths to the protos to be generated from.
    The input is a list of metadata attribute sets that at minimum provide the source location.

    # Example

    Given a source location `/store/path` with contents
    ./test/tester.proto
    ./test/message/data.proto

    ```nix
    toProtoPathsCMake {src = "/store/path;. } => "test/tester.proto;test/message/data.proto"
    ```

    # Type

    ```
    toProtoPathsCMake :: AttrSet -> String
    ```

    - [meta] An attribute set containing at minimum the src location of the base proto.

    - [returns] A string of semicolon separated of relative paths to the provided proto files.
  */
  toProtoPathsCMake =
    meta:
    concatMapStringsSep ";" (directory: removePrefix (meta.src + "/") directory) (
      filter (file: hasSuffix ".proto" file) (listFilesRecursive meta.src)
    );

  # Local files used in the code generation derivations
  grpcCmake = readFile ./CMakeLists.txt.grpc;
  protobufCmake = readFile ./CMakeLists.txt.protobuf;
  protobufCmakeConfig = readFile ./protoConfig.cmake.in;
  grpcCmakeConfig = readFile ./grpcConfig.cmake.in;
  utilCMake = readFile ./util.cmake;

  /*
    *
    Protobuf CPP derivation builds a cmake package based on the metadata provided by __proto_internal_meta_package.
    The derivation builds a shared library and the appropriate cmake config files to make the package relocatable
    # Type

    ```
    protobuf :: {pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> Deriation
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */
  protobuf =
    {
      pkgs,
      protobuf,
      cmake,
      stdenv,
      __proto_internal_meta_package,
    }:
    stdenv.mkDerivation rec {
      meta = loadMeta __proto_internal_meta_package;
      name = meta.name + "_proto_cpp";
      src = meta.src;
      version = meta.version;

      propagatedBuildInputs = [ protobuf ] ++ (toBuildDepsCpp meta.protoDeps pkgs);
      nativeBuildInputs = [
        cmake
      ]
      ++ optionals (stdenv.hostPlatform != stdenv.buildPlatform) [ pkgs.buildPackages.protobuf ];

      cmakeFlags = [
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-DCPP_NAME=${name}"
        "-DCPP_VERSION=${version}"
        "-DPROTOS=${toProtoPathsCMake meta}"
        "-DCPP_DEPS=${toCMakeDependencies meta.protoDeps}"
      ]
      ++ optionals (!pkgs.stdenv.hostPlatform.isStatic) [
        "-DBUILD_SHARED_LIBS=ON" # build shared libs by default
      ]
      ++ optionals (stdenv.hostPlatform != stdenv.buildPlatform) (
        let
          protobufVersion =
            if (lib.versionOlder protobuf.version "5") then
              "protobuf${lib.versions.major protobuf.version}_${lib.versions.minor protobuf.version}"
            else
              "protobuf_${lib.versions.major protobuf.version}";
        in
        [ "-DProtobuf_PROTOC_EXECUTABLE=${pkgs.buildPackages."${protobufVersion}"}/bin/protoc" ]
      );

      cmakeFile = pkgs.writeText "CMakeLists.txt" protobufCmake;
      cmakeFileConfig = pkgs.writeText "${name}Config.cmake.in" protobufCmakeConfig;
      utilCMakeFile = pkgs.writeText "util.cmake" utilCMake;

      prePatch = ''
        cp $cmakeFile CMakeLists.txt
        cp $cmakeFileConfig ${name}Config.cmake.in
        cp $utilCMakeFile util.cmake
      '';

      # There is a problem with newer version of Protobuf when generating GRPC code that causes a build failure without adding a local dir to the list of includes for the proto generation
      preConfigure = ''
        cmakeFlags="-DPROTO_DEPS=${(toProtoDepsCMake ((recursiveProtoDeps meta.protoDeps)))};$PWD $cmakeFlags"
      '';

      outputs = [
        "out"
        "dev"
      ];
      separateDebugInfo = !(lib.versionOlder protobuf.version "5");
    };

  /*
    *
    GRPC CPP derivation builds a cmake package based on the metadata provided by __proto_internal_meta_package.
    The derivation builds a shared library and the appropriate cmake config files to make the package relocatable
    # Type

    ```
    protobuf :: {pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> Derivation
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */
  grpc =
    {
      pkgs,
      cmake,
      protobuf,
      pkg-config,
      grpc,
      openssl,
      __proto_internal_meta_package,
    }:
    pkgs.stdenv.mkDerivation rec {
      meta = loadMeta __proto_internal_meta_package;
      name = meta.name + "_grpc_cpp";
      src = meta.src;
      version = meta.version;

      propagatedBuildInputs = [
        protobuf
        grpc
        openssl
      ]
      ++ (toBuildDepsCpp (meta.protoDeps ++ [ meta ]) pkgs);
      nativeBuildInputs = [
        cmake
      ]
      ++ optionals (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) [
        protobuf
        grpc
      ];
      propagatedNativeBuildInputs = [ pkg-config ]; # Needed because some cmake dependencies use pkg-config

      cmakeFlags = [
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-DCPP_NAME=${name}"
        "-DCPP_VERSION=${version}"
        "-DPROTOS=${toProtoPathsCMake meta}"
        "-DCPP_DEPS=${toCMakeDependencies (meta.protoDeps ++ [ meta ])}"
      ]
      ++ optionals (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) (
        let
          protobufVersion =
            if (lib.versionOlder protobuf.version "5") then
              "protobuf${lib.versions.major protobuf.version}_${lib.versions.minor protobuf.version}"
            else
              "protobuf_${lib.versions.major protobuf.version}";
        in
        [
          "-DProtobuf_PROTOC_EXECUTABLE=${pkgs.buildPackages."${protobufVersion}"}/bin/protoc"
          "-DgRPC_PLUGIN_EXECUTABLE=${pkgs.buildPackages.grpc}/bin/grpc_cpp_plugin"
          "-DCMAKE_CROSSCOMPILING=OFF" # Needed due to GRPC relying on the CMAKE_CROSSCOMPILING for adding the plugin targets
        ]
      )
      ++ optionals (!pkgs.stdenv.hostPlatform.isStatic) [
        "-DBUILD_SHARED_LIBS=ON" # build shared libs by default
      ];

      cmakeFile = pkgs.writeText "CMakeLists.txt" grpcCmake;
      cmakeFileConfig = pkgs.writeText "${name}Config.cmake.in" grpcCmakeConfig;
      utilCMakeFile = pkgs.writeText "util.cmake" utilCMake;

      prePatch = ''
        cp $cmakeFile CMakeLists.txt
        cp $cmakeFileConfig ${name}Config.cmake.in
        cp $utilCMakeFile util.cmake
      '';

      # There is a problem with newer version of Protobuf when generating GRPC code that causes a build failure without adding a local dir to the list of includes for the proto generation
      preConfigure = ''
        cmakeFlags="-DPROTO_DEPS=${(toProtoDepsCMake (recursiveProtoDeps meta.protoDeps))};$PWD $cmakeFlags"
      '';

      outputs = [
        "out"
        "dev"
      ];
      separateDebugInfo = !(lib.versionOlder protobuf.version "5");
    };
}
