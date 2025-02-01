{ lib }:
rec {
  inherit (lib.lists) forEach;
  inherit (lib.strings)
    escapeShellArg
    concatMapStringsSep
    concatStringsSep
    concatStrings
    ;
  inherit (lib)
    recursiveProtoDeps
    toProtocInclude
    loadMeta
    nixProtoWarn
    ;
  inherit (lib.versions) splitVersion;
  /*
    *
    Convert a set of attribute sets of metadata to a list of strings representing pyProjectTOML dependencies.

    # Example

    ```nix
    toPythonDependencies [{name = test; version = '1.1.1'; }] => ["test_proto_py>=1.1.1"]
    ```

    # Type

    ```
    toPythonDependencies :: List -> List
    ```

    - [deps] List of attribute sets minimally containing the name and version of the base proto.
    - [returns] List of Strings of the form `name>=version`
  */
  toPythonDependencies =
    deps:
    forEach deps (
      dep: builtins.toString (dep.name + "_proto_py") + ">=" + builtins.toString (dep.version)
    );

  /*
    *
    Takes metadata (name version and dependencies) and creates a PyProjectTOML

    # Type

    ```
    toPyProjectTOML :: {name :: String, version :: String, dependencies :: List } -> String
    ```
  */
  toPyProjectTOML = (import ./pyproj.nix) { inherit lib; };

  /*
    *
    Convert a set of attribute sets of metadata to a list of derivations looked up by name from the package set provided.

    # Type

    ```
    toBuildDepsPy :: List -> List
    ```

    - [deps] List of attribute sets minimally containing the name of the base proto.
    - [pkgs] Package set that this derivation will be built into.

    - [returns] List of derivations from the package set that the python package depends on.
  */
  toBuildDepsPy = deps: pkgs: forEach deps (dep: pkgs.${dep.name + "_proto_py"});
  /*
      *
    Convert a set of attribute sets of metadata to a list of derivations looked up by name from the package set provided.

      # Type

      ```
      toBuildDeps :: List -> List
      ```

      - [deps] List of attribute sets minimally containing the name of the base proto.
      - [pkgs] List of attribute sets minimally containing the name of the base proto.

      - [returns] List of derivations from the package set that the package depends on.
  */
  toBuildDepsDescriptor = deps: pkgs: forEach deps (dep: pkgs.${dep.name + "_proto_descriptor"});

  /*
    * For each dependency walk all the protos provided by that dependency
    * and for each of those walk every python file generated by this derivation
    * and patch the imports to point to the outer package "...proto_py" of the dependency
  */
  patchImports = name: fullProtoDeps: ''
    shopt -s globstar

    # Convert nix atterset to a map
    declare -A deps=${
      escapeShellArg (
        "("
        + (concatMapStringsSep " " (dep: "[\"" + dep.name + "\"]" + "=\"" + dep.src + "\"") fullProtoDeps)
        + ")"
      )
    }

    # Prefix all the imports with the container package
    echo Patching proto imports
    for dep in "''${!deps[@]}"; do
        for proto in `find "''${deps[''${dep}]}" -type f -name "*.proto"`; do
          path=$(realpath --relative-to="''${deps[''${dep}]}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././;s/\.[^.]*$//')
          echo patching imports from $path -> ''${dep}_proto_py.$path
          for py in `find "./src/${name}" -type f -name "*_pb2*.py"`; do
            # Handle the case where there is a namespace for the proto
            sed -i "s/from\ $path\ import/from\ ''${dep}_proto_py.$path\ import/g" $py
            # Handle the imports when there is no namespace
            sed -i "s/import\ $path/from\ ''${dep}_proto_py\ import $path/g" $py
        done
      done
    done
  '';

  /*
    *
    Protobuf python derivation for a given set of protos.

    # Type

    ```
    package :: { pkgs :: AttrSet, __proto_internal_meta_package :: AttrSet, python :: AttrSet, buildPackages :: AttrSet, substituteAll :: Function, writeTextFile :: Function } -> Derivation
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
    - [python] Python as input by callPackage this is important for pythonPackagesExtensions
    - [buildPackages] Build platform package. Used to get deps that run at build time.
    - [substituteAll] Function to create a file with substitutions.
    - [writeTextFile] function to write a text file from a string.
  */
  protobuf =
    {
      pkgs,
      __proto_internal_meta_package,
      python,
      substituteAll,
      writeTextFile,
    }:
    let
      # Python Dependencies
      inherit (python.pkgs) buildPythonPackage protobuf;
      # Native build dependencies `python.pythonForBuild` is deprecated remove when 23.05 is no longer supported
      inherit ((python.pythonOnBuildForHost or python.pythonForBuild).pkgs) setuptools;

      # Package meta data
      protoMeta = loadMeta __proto_internal_meta_package;
      name = protoMeta.name + "_proto_py";
      inherit (protoMeta) version src protoDeps;
      fullProtoDeps = recursiveProtoDeps protoDeps ++ [ protoMeta ];
      dependencies = [ protobuf ] ++ (toBuildDepsPy protoDeps python.pkgs);

      # Generate each proto file using protoc and add the generated code to the __init__.py file to allow for top level imports
      descriptor_py = substituteAll {
        src = ./descriptor.py;
        package = protoMeta.name + "_proto_py";
      };
      descriptors = writeTextFile {
        name = "descriptors.txt";
        text = concatStringsSep "\n" (toBuildDepsDescriptor fullProtoDeps pkgs);
      };

      # Create the pyproject.toml and patch the imports
      py_project_toml = toPyProjectTOML {
        inherit name version;
        dependencies = [ "protobuf" ] ++ toPythonDependencies protoDeps;
        pythonVersion = python.pythonVersion;
      };
      postPatch = (patchImports name fullProtoDeps) + py_project_toml;
    in
    buildPythonPackage {
      inherit
        name
        version
        src
        dependencies
        postPatch
        ;
      pyproject = true;

      nativeBuildInputs = [ setuptools ]; # for import checking
      propagatedBuildInputs = dependencies; # This is needed because `dependencies` only works on unstable right now

      prePatch = ''
        mkdir -p src/${name}
        echo Adding descriptor files to src/${name}
        cp ${descriptor_py} src/${name}/descriptor.py
        cp ${descriptors}  src/${name}/descriptors.txt
        shopt -s globstar

        echo Generating python with protoc output to src/${name}
        for proto in `find "${protoMeta.src}" -type f -name "*.proto"`; do
          echo "generating $proto"
          protoc ${(toProtocInclude fullProtoDeps)} \
          --python_out=src/${name} \
          --pyi_out=src/${name} \
          $proto

          import_path="from .$(realpath --relative-to="${src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *"
          echo "adding $import_path to src/${name}/__init__.py"
          echo "from .$(realpath --relative-to="${src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${name}/__init__.py
        done

        echo Add descriptor import
        descriptor_import="from .descriptor import file_descriptor_set as ${protoMeta.name}_descriptors"
        echo adding $descriptor_import to src/${name}/__init__.py
        echo $descriptor_import >> src/${name}/__init__.py
      '';
    };

  /*
    *
    GRPC python derivation for a given set of protos.

    # Type

    ```
    package :: { pkgs :: AttrSet, __proto_internal_meta_package :: AttrSet, python :: AttrSet, buildPackages :: AttrSet, substituteAll :: Function, writeTextFile :: Function } -> Derivation
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
    - [python] Python as input by callPackage this is important for pythonPackagesExtensions
    - [buildPackages] Build platform package. Used to get deps that run at build time.
  */
  grpc =
    {
      pkgs,
      __proto_internal_meta_package,
      python,
    }:
    let
      # Native build dependencies `python.pythonForBuild` is deprecated remove when 23.05 is no longer supported
      inherit ((python.pythonOnBuildForHost or python.pythonForBuild).pkgs) grpcio-tools setuptools;

      # Python dependencies pulled from the given python package
      inherit (python.pkgs) buildPythonPackage protobuf grpcio;

      # Package information
      protoMeta = loadMeta __proto_internal_meta_package;
      name = protoMeta.name + "_grpc_py"; # TODO: Allow user to customize name
      inherit (protoMeta) version src;
      fullProtoDeps = recursiveProtoDeps protoMeta.protoDeps ++ [ protoMeta ];
      dependencies = [
        protobuf
        grpcio
      ] ++ (toBuildDepsPy (protoMeta.protoDeps ++ [ protoMeta ]) python.pkgs); # Pull python deps from the current python package set

      # PyProjectTOML file for generated code
      py_project_toml = toPyProjectTOML {
        inherit name;
        inherit (protoMeta) version;
        dependencies = [
          "protobuf"
          "grpcio"
        ] ++ toPythonDependencies (protoMeta.protoDeps ++ [ protoMeta ]);
        pythonVersion = python.pythonVersion;
      };

      # Create the pyproject.toml and patch the imports
      postPatch = (patchImports name fullProtoDeps) + py_project_toml;
    in
    buildPythonPackage {
      inherit
        name
        version
        src
        dependencies
        postPatch
        ;
      pyproject = true;

      nativeBuildInputs = [
        grpcio-tools
        setuptools
      ]; # for import checking
      propagatedBuildInputs = dependencies; # This is needed because `dependencies` only works on unstable right now

      # Generate the GRPC stubs / servers
      prePatch = ''
        mkdir -p src/${name}
        shopt -s globstar
        for proto in `find "${src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${toProtocInclude fullProtoDeps} --grpc_python_out=src/${name} $proto
          echo "from .$(realpath --relative-to="${src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2_grpc import *" >> src/${name}/__init__.py
        done
      '';
    };

  /*
    *
    Base function called by both grpc and protobuf generation targets to make a python package.

    Provides a postPatch script that changes the imports in the protobuf generated code to include the top level package created by nix.
    This enforces a unique name for the python package. Also creates a pyproject TOML using the metadata provided.

    # Type

    ```
    package :: { pkgs :: AttrSet, suffix :: String, inputPatchPhase :: String, buildInputs :: List, inputDependencies :: List, proto_meta :: AttrSet } -> Derivation
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [suffix] Suffix to apply to the base name of the proto.
    - [inputPatchPhase] Patch phase to run for this derivation.
    - [buildInputs] Additional package dependencies.
    - [inputDependencies] Additional python package dependencies.
    - [proto_meta] metadata about the protos used to generate the python (name, version, etc.).
  */
  package =
    {
      pkgs,
      suffix,
      inputPatchPhase,
      buildInputs,
      nativeInputs ? [ ],
      inputDependencies,
      proto_meta,
      ...
    }:
    pkgs.python3Packages.buildPythonPackage rec {
      name = proto_meta.name + suffix;
      version = proto_meta.version;
      src = proto_meta.src;
      doCheck = false;
      pyproject = true;

      dependencies = [
        pkgs.python3Packages.protobuf
      ] ++ (toBuildDepsPy proto_meta.protoDeps pkgs) ++ buildInputs;
      nativeBuildInputs = [
        pkgs.buildPackages.protobuf
        pkgs.buildPackages.python3Packages.setuptools
      ] ++ nativeInputs ++ dependencies; # for import checking
      propagatedBuildInputs = dependencies; # This is needed because `dependencies` only works on unstable right now

      py_project_toml = toPyProjectTOML {
        inherit name;
        inherit version;
        dependencies = inputDependencies ++ [ "protobuf" ] ++ toPythonDependencies proto_meta.protoDeps;
        pythonVersion = pkgs.python3.pythonVersion;
      };

      prePatch = ''
        mkdir -p src/${name}
      '';

      patchPhase = inputPatchPhase;

      postPatch =
        (patchImports name (recursiveProtoDeps proto_meta.protoDeps ++ [ proto_meta ])) + py_project_toml;
    };

  /*
    *
    DEPRECATED: use the protobuf derivation it is built to support `pythonPackagesExtensions` by taking python has an argument
    Protobuf inputs to the `package` function.
    Pulls the meta data from the `__proto_internal_meta_package` and provides a patch phase to run protoc and patch the generated files.

    # Type

    ```
    protobuf :: { pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> (AttrSet -> Derivation)
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */

  protobufLegacy =
    { pkgs, __proto_internal_meta_package }:
    nixProtoWarn
      "Deprecated: use the protobuf derivation it is built to support `pythonPackagesExtensions` by taking python has an argument"
      package
      rec {
        inherit pkgs;
        proto_meta = loadMeta __proto_internal_meta_package;
        suffix = "_proto_py";
        # * Generate each proto file using protoc and add the generated code to the __init__.py file to allow for top level imports
        descriptor_py = pkgs.substituteAll {
          src = ./descriptor.py;
          package = proto_meta.name + suffix;
        };

        descriptors = pkgs.writeTextFile {
          name = "descriptors.txt";
          text = concatStringsSep "\n" (
            toBuildDepsDescriptor ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ]) pkgs
          );
        };

        inputPatchPhase = ''
          runHook prePatch
          shopt -s globstar
          cp ${descriptor_py} src/${proto_meta.name + suffix}/descriptor.py
          cp ${descriptors}  src/${proto_meta.name + suffix}/descriptors.txt
          for proto in `find "${proto_meta.src}" -type f -name "*.proto"`; do
            protoc ${(toProtocInclude ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ]))} \
            --python_out=src/${proto_meta.name + suffix} \
            --pyi_out=src/${proto_meta.name + suffix} \
            $proto
            echo  "from .$(realpath --relative-to="${proto_meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2 import *" >> src/${proto_meta.name + suffix}/__init__.py
          done
          echo "from .descriptor import file_descriptor_set as ${proto_meta.name}_descriptors" >> src/${proto_meta.name + suffix}/__init__.py
          runHook postPatch
        '';
        inputDependencies = [ ];
        buildInputs = [ ];
      };

  /*
    *
    DEPRECATED: use the grpc derivation it is built to support `pythonPackagesExtensions` by taking python has an argument
    GRPC inputs to the `package` function.
    Pulls the meta data from the `__proto_internal_meta_package` and provides a patch phase to run grpc_tools.protoc and patch the generated files.

    # Type

    ```
    protobuf :: { pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> (AttrSet -> Derivation)
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */
  grpcLegacy =
    { pkgs, __proto_internal_meta_package }:
    package rec {
      inherit pkgs;
      proto_meta = loadMeta __proto_internal_meta_package;
      suffix = "_grpc_py";
      buildInputs = [
        pkgs.python3Packages.grpcio
        pkgs.python3Packages.grpcio-tools
        pkgs.grpc
        pkgs.openssl
        pkgs.zlib
      ] ++ (toBuildDepsPy [ proto_meta ] pkgs);
      nativeInputs = [ pkgs.buildPackages.python3Packages.grpcio-tools ];
      inputDependencies = [ "grpcio" ];
      # * Generate each proto file using grpcio and add the generated code to the __init__.py file to allow for top level imports
      inputPatchPhase = ''
        runHook prePatch
        shopt -s globstar
        for proto in `find "${proto_meta.src}" -type f -name "*.proto"`; do
          python -m grpc_tools.protoc ${
            (toProtocInclude ((recursiveProtoDeps proto_meta.protoDeps) ++ [ proto_meta ]))
          } --grpc_python_out=src/${proto_meta.name + suffix} $proto
          echo  "from .$(realpath --relative-to="${proto_meta.src}" "$proto" | sed 's/\.[^.]*$//;s/[/]/./g;s/*[.]\././')_pb2_grpc import *" >> src/${proto_meta.name + suffix}/__init__.py
        done
        runHook postPatch
      '';
    };
}
