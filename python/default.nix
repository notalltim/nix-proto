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
    propagatedBuildInputs = buildDeps;
    doCheck = false;

    format = "pyproject";
    pyproject = true;
    dependencies = inputDependencies ++ [ "protobuf" ] ++ toPythonDependencies meta.protoDeps;
    py_project_toml = toPyProjectTOML { inherit name; inherit version; inherit dependencies; };

    prePatch = ''
      mkdir -p src/${name}
    '';
    patchPhase = inputPatchPhase;
    postPatch = ''
      for d in src/**/*/; do touch -- "$d/__init__.py"; done
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
        path=$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././;s/\.[^.]*$//')
        for py in `find "./src/${meta.name + suffix}" -type f -name "*_pb2.py"`; do
          sed -i "s/from\ $path/from\ ./g" $py
        done
        runHook postPatch
      '';
    inputDependencies = [ ];
    buildInputs = [ ];
  };

  grpc_package = { python310Packages, protobuf, pkgs, grpc, openssl, zlib, stdenv }: package rec {
    inherit python310Packages;
    inherit protobuf;
    inherit pkgs;
    suffix = "_grpc_py";
    buildInputs = [ python310Packages.grpcio python310Packages.grpcio-tools grpc openssl zlib stdenv ] ++ (toBuildDepsPy [ meta ] pkgs);
    inputDependencies = [ "grpcio" ];
    inputPatchPhase =
      ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${ (proto_lib.toProtocInclude (meta.protoDeps ++ [ meta ]))} --grpc_python_out=src/${meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2_grpc import *" >> src/${meta.name + suffix}/__init__.py
        done
        path=$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././;s/\.[^.]*$//')
        for py in `find "./src/${meta.name + suffix}" -type f -name "*_pb2_grpc.py"`; do
          sed -i "s/from\ $path/from\ ${meta.name}_proto_py.$path/g" $py
        done
        runHook postPatch
      '';
  };
}
