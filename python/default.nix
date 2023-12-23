{ lib }: rec {
  inherit (lib.lists) forEach;
  inherit (lib.strings) escapeShellArg concatMapStringsSep;
  inherit (lib) recursiveProtoDeps toProtocInclude;

  toPythonDependencies = x: forEach x (a: builtins.toString (a.name + "_proto_py") + ">=" + builtins.toString (a.version));
  toPyProjectTOML = (import ./pyproj.nix) { inherit lib; };
  toBuildDepsPy = x: pkgs: forEach x (a: pkgs.${a.name + "_proto_py"});



  package = { python310Packages, protobuf, pkgs, suffix, inputPatchPhase, buildInputs, inputDependencies, proto_meta}: python310Packages.buildPythonPackage rec {
    name = proto_meta.name + suffix;
    version = proto_meta.version;
    src = proto_meta.src;

    buildDeps = [ python310Packages.protobuf ] ++ (toBuildDepsPy proto_meta.protoDeps pkgs) ++ buildInputs;
    nativeBuildInputs = [ protobuf python310Packages.setuptools ] ++ buildDeps; # for import checking
    propagatedBuildInputs = buildDeps;
    doCheck = false;

    pyproject = true;

    dependencies = inputDependencies ++ [ "protobuf" ] ++ toPythonDependencies proto_meta.protoDeps;
    py_project_toml = toPyProjectTOML { inherit name; inherit version; inherit dependencies; };

    prePatch = ''
      mkdir -p src/${name}
    '';
    patchPhase = inputPatchPhase;
    postPatch = ''
      shopt -s globstar
      declare -A deps=${escapeShellArg("(" + (concatMapStringsSep " " (dep: "[\"" +  dep.name + "\"]" + "=\"" + dep.src + "\"")  ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ])) + ")")}
      # Prefix all the imports with the container package
      echo "Patching proto imports"
      for dep in "''${!deps[@]}"; do
          for proto in `find "''${deps[''${dep}]}" -type f -name "*.proto"`; do
            path=$(realpath --relative-to="''${deps[''${dep}]}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././;s/\.[^.]*$//')
            for py in `find "./src/${proto_meta.name + suffix}" -type f -name "*_pb2*.py"`; do
              sed -i "s/from\ $path\ import/from\ ''${dep}_proto_py.$path\ import/g" $py
          done
        done
      done

      cat > pyproject.toml << EOF ${py_project_toml}
      EOF
      cat > setup.py << EOF
      from setuptools import setup
      setup()
      EOF
    '';
  };

  gen_protobuf = { python310Packages, protobuf, pkgs , __proto_internal_meta_package}: package rec {
    inherit python310Packages;
    inherit protobuf;
    inherit pkgs;
    proto_meta = (lib.tryLoadMeta __proto_internal_meta_package);
    suffix = "_proto_py";
    inputPatchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${proto_meta.src}" -type f -name "*.proto"`; do
          protoc ${(toProtocInclude ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ]))} --python_out=src/${proto_meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${proto_meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${proto_meta.name + suffix}/__init__.py
        done
        runHook postPatch
      '';
    inputDependencies = [ ];
    buildInputs = [ ];
  };

  gen_grpc = { python310Packages, protobuf, pkgs, grpc, openssl, zlib, stdenv, __proto_internal_meta_package }: package rec {
    inherit python310Packages;
    inherit protobuf;
    inherit pkgs;
    proto_meta = (lib.tryLoadMeta __proto_internal_meta_package);
    suffix = "_grpc_py";
    buildInputs = [ python310Packages.grpcio python310Packages.grpcio-tools grpc openssl zlib stdenv ] ++ (toBuildDepsPy [ proto_meta ] pkgs);
    inputDependencies = [ "grpcio" ];
    inputPatchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${proto_meta.src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${ (toProtocInclude ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ]))} --grpc_python_out=src/${proto_meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${proto_meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2_grpc import *" >> src/${proto_meta.name + suffix}/__init__.py
        done
        runHook postPatch
      '';
  };
}
