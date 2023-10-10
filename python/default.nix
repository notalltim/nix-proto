{ meta, proto_lib }: rec {

  toPythonDependencies = x: proto_lib.lists.forEach x (a: builtins.toString (a.name + "_proto_py") + ">=" + builtins.toString (a.version));
  toPyProjectTOML = (import ./pyproj.nix) { std = proto_lib; };
  toBuildDepsPy = x: pkgs: proto_lib.lists.forEach x (a: pkgs.${a.name + "_proto_py"});

  package = { python310Packages, protobuf, pkgs }: python310Packages.buildPythonPackage rec {
    name = meta.name + "_proto_py";
    version = meta.version;
    src = meta.src;

    buildDeps = [ python310Packages.protobuf ] ++ (toBuildDepsPy meta.protoDeps pkgs);
    nativeBuildInputs = [ protobuf python310Packages.setuptools ] ++ buildDeps; # for import checking
    propagateBuildInputs = buildDeps;
    doCheck = false;

    format = "pyproject";
    dependencies = [ "protobuf" ] ++ toPythonDependencies meta.protoDeps;
    py_project_toml = toPyProjectTOML { inherit name; inherit version; inherit dependencies; };

    protoPaths = (proto_lib.toProtocInclude (meta.protoDeps ++ [ meta ]));
    patchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        mkdir -p src/${name}
        echo ${protoPaths}
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          protoc ${protoPaths} --python_out=src/${name} $proto
          echo  "from .$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${name}/__init__.py
        done
        runHook postPatch
      '';
    postPatch = ''
      cat > pyproject.toml << EOF ${py_project_toml}
      EOF
    '';
  };

  grpc_package = { python310Packages, protobuf, pkgs, grpc }: python310Packages.buildPythonPackage rec {
    name = meta.name + "_grpc_py";
    version = meta.version;
    src = meta.src;

    buildDeps = [ python310Packages.protobuf grpc python310Packages.grpcio ] ++ (toBuildDepsPy meta.protoDeps pkgs);
    nativeBuildInputs = [ protobuf python310Packages.setuptools python310Packages.grpcio-tools python310Packages.grpcio ] ++ buildDeps; # for import checking
    propagateBuildInputs = buildDeps;
    doCheck = false;

    format = "pyproject";
    dependencies = [ "protobuf" "grpcio" ] ++ toPythonDependencies meta.protoDeps;
    py_project_toml = toPyProjectTOML { inherit name; inherit version; inherit dependencies; };

    protoPaths = (proto_lib.toProtocInclude (meta.protoDeps ++ [ meta ]));
    patchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        mkdir -p src/${name}
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${protoPaths} --python_out=. --grpc_python_out=src/${name} $proto
          echo  "from .$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${name}/__init__.py
        done
        runHook postPatch
      '';
    postPatch = ''
      cat > pyproject.toml << EOF ${py_project_toml}
      EOF
    '';
  };
}
