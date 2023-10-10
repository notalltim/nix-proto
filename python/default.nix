{ meta, proto_lib }: rec {

  toPythonDependencies = x: proto_lib.lists.forEach x (a: builtins.toString (a.name + "_proto_py") + ">=" + builtins.toString (a.version));
  toPyProjectTOML = (import ./pyproj.nix) { std = proto_lib; };
  toBuildDepsPy = x: pkgs: proto_lib.lists.forEach x (a: pkgs.${a.name + "_proto_py"});



  package = { python310Packages, protobuf, pkgs, suffix, inputPatchPhase, buildInputs, inputDependencies }: python310Packages.buildPythonPackage rec {
    name = meta.name + suffix;
    version = meta.version;
    src = meta.src;

    buildDeps = [ python310Packages.protobuf ] ++ (toBuildDepsPy meta.protoDeps pkgs) ++ buildInputs;
    nativeBuildInputs = [ protobuf python310Packages.setuptools ] ++ buildDeps; # for import checking
    propagateBuildInputs = buildDeps;
    doCheck = false;

    format = "pyproject";
    dependencies = inputDependencies ++ [ "protobuf" ] ++ toPythonDependencies meta.protoDeps;
    py_project_toml = toPyProjectTOML { inherit name; inherit version; inherit dependencies; };

    prePatch = ''
      mkdir -p src/${name}
    '';
    patchPhase = inputPatchPhase;
    postPatch = ''
      cat > pyproject.toml << EOF ${py_project_toml}
      EOF
    '';
  };

  proto_package = { python310Packages, protobuf, pkgs }: package rec {
    inherit python310Packages;
    inherit protobuf;
    inherit pkgs;
    suffix = "_proto_py";
    inputPatchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          protoc ${(proto_lib.toProtocInclude (meta.protoDeps ++ [ meta ]))} --python_out=src/${meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${meta.name + suffix}/__init__.py
        done
        runHook postPatch
      '';
    inputDependencies = [ ];
    buildInputs = [ ];
  };

  grpc_package = { python310Packages, protobuf, pkgs, grpc }: package rec {
    inherit python310Packages;
    inherit protobuf;
    inherit pkgs;
    suffix = "_grpc_py";
    buildInputs = [ grpc python310Packages.grpcio python310Packages.grpcio-tools ];
    inputDependencies = [ "grpcio" ];
    inputPatchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${ (proto_lib.toProtocInclude (meta.protoDeps ++ [ meta ]))} --grpc_python_out=src/${meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_grpc_pb2 import *" >> src/${meta.name + suffix}/__init__.py
        done
        runHook postPatch
      '';
  };
}
