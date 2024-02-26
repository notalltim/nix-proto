{lib}: rec {
  /*
  *
  Make a derivation from an attribute set that installs proto files provided in the src path to the store and propagate generation metadata.
  Used in combination with `generateOverlays'` it can produce a set of packages generated from the protos that are provided by the user.
  This mimics the mkDerivation pattern to for building overlays.

  The minimum set of information needed is
  - `src` path to the protos
  - `name` name to be used as the base name for the generated packages
  Optional Additional information
  - `version` - version of the protos to be generated
  - `protoDeps` - list of packages generated by this function needed to generate the protos at `src`

  **NOTE**: The name given to this function must match the attribute name to `generateOverlays'` for this derivation.

  # Example

  With a function
  ```nix
  my_apis = { dependent_api } : mkProtoDerivation {
    name = "my_apis";
    version = "0.1.0";
    src = ./proto;
    protoDeps = [ dependent_api ];
  }
  => { dependent_api } : { stdenvNoCC } : stdenvNoCC.mkDerivation {
    name = "my_apis";
    version = "0.1.0";
    src = ./proto;
    propagatedBuildInputs = [ dependent_api ];
    # other metadata
  }
  ```

  With a attribute set
  ```nix
  base_api = mkProtoDerivation {
    name = "base_api";
    version = "0.1.0";
    src = ./proto;
    protoDeps = [ ];
  }
  => { stdenvNoCC } : stdenvNoCC.mkDerivation {
    name = "my_apis";
    version = "0.1.0";
    src = ./proto;
    propagatedBuildInputs = [ ];
  # other metadata
  }
  ```

  # Type

  ```
  mkProtoDerivation :: AttrSet -> ({ stdenvNoCC :: AttrSet }  -> Derivation)
  ```

  - [set] User provided attribute set used to build the internal derivation.

  - [returns] derivation made with a combination of custom and user provided attributes using `stdenvNoCC`.
  */
  mkProtoDerivation = set: {stdenvNoCC}:
    stdenvNoCC.mkDerivation (set
      // {
        version =
          if set ? version
          then set.version
          else "0.0.0";
        propagatedBuildInputs =
          if set ? protoDeps
          then set.protoDeps
          else [];
        installPhase = ''
          runHook preInstall
          cp -r . $out
          runHook postInstall
        '';
        #TODO(notalltim): Add user generation options
        # - allow user to control language specific naming through suffix
        # - allow the user to specify a install namespace that does not match source
      });

  /*
  *
  Generates a set of overlays given an attribute set of derivations generated from `mkProtoDerivation`.
  The overlays are returned as an attribute set with the same names with '_overlay' appended.
  The returned attribute set can be flattened using `overlayToList` to pass to `legacyPackages`

  # Example

  ```nix
  generateOverlays' {
    base_api = mkProtoDerivation {
      name = "base_api";
      version = "0.1.0";
      src = ./proto;
      protoDeps = [ ];
    };
    ...
  } => { base_api_overlay = final: prev: ...; ... }
  ```

  # Type

  ```
  generateOverlays' :: AttrSet -> AttrSet
  ```

  # Arguments

  - [set] User provided attribute set of calls to `mkProtoDerivation`

  - [returns] Attribute set of overlays (functions of the form final: prev:)
  */
  generateOverlays' = set: let
    inherit (lib.attrsets) mapAttrs' nameValuePair;
  in
    mapAttrs' (name: drv:
      nameValuePair (name + "_overlay") (generateOverlay' {
        inherit drv;
        inherit name;
      }))
    set;

  /*
  * Proto Generation (Deprecated)
  */
  generateProto = ((import ./proto) {inherit lib;}).package;
  /*
  * Python Generation
  */
  pythonGenerators = (import ./python) {inherit lib;};
  /*
  * Generate a python module for protobuf generation
  */
  generatePython = pythonGenerators.protobuf;
  /*
  * Generate a python module for grpc generation
  */
  generateGRPCPython = pythonGenerators.grpc;

  /*
  * Cpp Generation
  */
  cppGenerators = (import ./cpp) {inherit lib;};
  /*
  * Generate a cpp library for protobuf generation
  */
  generateCpp = cppGenerators.protobuf;
  /*
  * Generate a cpp library for grpc generation
  */
  generateGRPCCpp = cppGenerators.grpc;

  /*
  *
  Create a set of derivation to evaluate with `generateOverlay'`
  # Example

  ```nix
    generateDerivations { name = "test_apis"; }
    => { test_apis_cpp = Derivation; test_apis_python = Derivation; ...}
  ```

  # Type

  ```
  generateDerivations :: { name :: String } -> AttrSet
  ```

  - [name] Base name of the generated packages.

  - [returns] Attribute set of code generation derivations.
  */
  generateDerivations = {name}: rec {
    ${name + "_proto_" + "drv"} = generateProto;
    ${name + "_proto_" + "py_drv"} = generatePython;
    ${name + "_grpc_" + "py_drv"} = generateGRPCPython;
    ${name + "_proto_" + "cpp_drv"} = generateCpp;
    ${name + "_grpc_" + "cpp_drv"} = generateGRPCCpp;
  };

  /*
  *
  Determine if a derivation is an internal function or a user function
  # Example

  ```nix
  # produces double `callPackage`
  evaluateProtoDerivation {} : {} : {}
  # produces single `callPackage`
  evaluateProtoDerivation {} : {}
  }
  ```

  # Type

  ```
  evaluateProtoDerivation :: (AttrSet -> (AttrSet -> Derivation)) -> (PkgSet -> Package)
  evaluateProtoDerivation :: (AttrSet -> Derivation) -> (PkgSet -> Package)
  ```

  # Arguments

  - [input] function to evaluate

  - [returns] function to be called in an overlay function
  */
  evaluateProtoDerivation = input: let
    inherit (lib.trivial) functionArgs;
    doubleCall = !((functionArgs input) ? stdenvNoCC); # Check if the user passed a function or if this is the internal derivation
  in
    if doubleCall
    then final: (final.callPackage (final.callPackage input {}) {})
    else final: (final.callPackage input {});

  /*
  *
  Internal function to take meta derivation and produces a set of overlays for supported codgen targets.
  The function maps the attribute stet of derivation to a set of overlays called with a specific `callPackage` signature

  ```nix
  language_specific_name = prev.callPackage language_specific_derivation { __proto_internal_meta_package };
  ```

  This overrides a marker package `__proto_internal_meta_package` to the metadata required to evaluate the code generation derivation.
  The marker package is attached to the overlay as well to allow for dependency propagation of the proto with the overlay produced.

  # Example

  ```nix
    generateOverlay' { drv = {} : {}; name = "package_name"}
  } => { package_name_cpp = ...; package_name_py = ...; ...}
  ```

  # Type

  ```
  generateOverlay' :: {drv :: Derivation, name :: String} -> (PkgSet -> PkgSet -> Package)
  ```

  # Arguments

  - [drv] meta derivation used to generate the codegen derivations
  - [name] name to use for the overlay

  - [returns] overlay function with an output of an attribute set of language specific packages.
  */
  generateOverlay' = {
    drv,
    name,
  }: let
    inherit (lib.attrsets) mapAttrs' nameValuePair;
    inherit (lib.strings) removeSuffix;
    package = evaluateProtoDerivation drv;
    derivations = generateDerivations {inherit name;};
  in
    final: _:
      (mapAttrs' (key: value: nameValuePair (removeSuffix "_drv" key) (final.callPackage value {__proto_internal_meta_package = package final;})) derivations)
      // rec {${name} = package final;};
}
