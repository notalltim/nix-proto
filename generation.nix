{ lib }:
rec {
  inherit (lib.attrsets) mapAttrs' nameValuePair filterAttrs;
  inherit (lib.strings) removeSuffix hasSuffix;
  inherit (lib.fixedPoints) composeManyExtensions;
  inherit (lib) nixProtoWarn overlayToList;
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
  mkProtoDerivation =
    set:
    { stdenvNoCC }:
    stdenvNoCC.mkDerivation (
      set
      // {
        version = if set ? version then set.version else "0.0.0";
        propagatedBuildInputs = if set ? protoDeps then set.protoDeps else [ ];
        installPhase = ''
          runHook preInstall
          cp -r . $out
          runHook postInstall
        '';
        #TODO(notalltim): Add user generation options
        # - allow user to control language specific naming through suffix
        # - allow the user to specify a install namespace that does not match source
      }
    );

  /*
    *
    Generates a set of overlays given an attribute set of derivations generated from `mkProtoDerivation`.
    The overlays are returned as an attribute set with the same names with '_overlay' appended.
    The returned attribute set can be flattened using `overlayToList` to pass to `legacyPackages`.
    Additionally a `default` attribute is given that composes all the overlays.

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
    } => {
            base_api_overlay = final: prev: ...;
            default = final: prev: ...;
         }
    ```

    # Type

    ```
    generateOverlays' :: AttrSet -> AttrSet
    ```

    # Arguments

    - [set] User provided attribute set of calls to `mkProtoDerivation`

    - [returns] Attribute set of overlays (functions of the form final: prev:)
  */
  generateOverlays' =
    set:
    let
      # Export the individual overlays
      overlayAttrs = mapAttrs' (
        name: drv:
        nameValuePair (name + "_overlay") (generateOverlay' {
          inherit drv;
          inherit name;
        })
      ) set;

      # Composition of all the overlays in the set
      default = composeManyExtensions (overlayToList overlayAttrs);
    in
    overlayAttrs // { inherit default; };

  # * Proto Generation (Deprecated)
  generateProto = ((import ./proto) { inherit lib; }).package;
  # * Python Generation
  pythonGenerators = (import ./python) { inherit lib; };
  # * Generate a python module for protobuf generation
  generatePython = nixProtoWarn "generatePython is deprecated use the generatePython' derivation it is built to support `pythonPackagesExtensions` by taking python has an argument" pythonGenerators.protobufLegacy;
  generatePython' = pythonGenerators.protobuf;
  # * Generate a python module for grpc generation
  generateGRPCPython = nixProtoWarn "generateGRPCPython is deprecated use the generateGRPCPython' derivation it is built to support `pythonPackagesExtensions` by taking python has an argument" pythonGenerators.grpcLegacy;
  generateGRPCPython' = pythonGenerators.grpc;

  # * Cpp Generation
  cppGenerators = (import ./cpp) { inherit lib; };
  # * Generate a cpp library for protobuf generation
  generateCpp = cppGenerators.protobuf;
  # * Generate a cpp library for grpc generation
  generateGRPCCpp = cppGenerators.grpc;

  # * Generate proto descriptors

  generateDescriptor = ((import ./descriptor) { inherit lib; }).package;

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
  generateDerivations = name: {
    ${name + "_proto_" + "drv"} = nixProtoWarn "${name}_proto is deperacted use ${name} for the functionality" generateProto;
    ${name + "_proto_" + "cpp_drv"} = generateCpp;
    ${name + "_grpc_" + "cpp_drv"} = generateGRPCCpp;
    ${name + "_proto_" + "descriptor_drv"} = generateDescriptor;
  };

  /*
    *
    Create a set of python derivation to evaluate with `generateOverlay'`.
    Python derivations are separated because they need to be overridden in all the `pythonPackages` scopes.

    # Example

    ```nix
      generateDerivations { name = "test_apis"; }
      => { test_apis_cpp = Derivation; test_apis_python = Derivation; ...}
    ```

    # Type

    ```
    generatePythonDerivations :: String -> AttrSet
    ```

    - [name] Base name of the generated packages.

    - [returns] Attribute set of python derivations.
  */
  generatePythonDerivations = name: {
    ${name + "_proto_" + "py_drv"} = generatePython';
    ${name + "_grpc_" + "py_drv"} = generateGRPCPython';
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
  evaluateProtoDerivation =
    input:
    let
      inherit (lib.trivial) functionArgs;
      doubleCall = !((functionArgs input) ? stdenvNoCC); # Check if the user passed a function or if this is the internal derivation
    in
    if doubleCall then
      final: (final.callPackage (final.callPackage input { }) { })
    else
      final: (final.callPackage input { });
  /*
    *
    Internal function to take meta derivation and produces a set of overlays for supported codgen targets.
    The function maps the attribute set of derivations to a set of overlays called with a specific `callPackage` signature

    ```nix
    language_specific_name = final.callPackage language_specific_derivation { inherit __proto_internal_meta_package; };
    ```

    This overrides a marker package `__proto_internal_meta_package` to the metadata required to evaluate the code generation derivation.
    The marker package is attached to the overlay as well to allow for dependency propagation of the proto with the overlay produced.

    Addiontionally language specific overlay strategies are applied such as `pythonPackagesExtensions` for python.

    # Example

    ```nix
      createLanguageOverlay { drv = {} : {}; name = "package_name"}
    } => { package_name_cpp = ...; package_name_py = ...; ...}
    ```

    # Type

    ```
    createLanguageOverlay :: String -> Overlay -> (PkgSet -> PkgSet -> AttrSet)
    ```

    # Arguments

    - [drv] meta derivation used to generate the codegen derivations
    - [name] name to use for the overlay

    - [returns] overlay function with an output of an attribute set of language specific packages.
  */
  createLanguageOverlay =
    name: protoOverlay:
    let
      defaultOveralyDrvs = generateDerivations name;
      pythonOverlayDrvs = generatePythonDerivations name;
    in
    final: prev:
    let
      protoPackage = protoOverlay final;
      convertDerivationToOverlay =
        final: set:
        (mapAttrs' (
          key: value:
          nameValuePair (removeSuffix "_drv" key) (
            final.callPackage value {
              __proto_internal_meta_package =
                lib.throwIf (name != protoPackage.name)
                  "name passed to `generateOverlay'` (${name}) and `mkProtoDerivation` (${protoPackage.name}) do not match ${name} != ${protoPackage.name}"
                  protoPackage;
            }
          )
        ) set);
    in
    # Standard callPackage based overlays
    (convertDerivationToOverlay final defaultOveralyDrvs)
    //
      # Extend all pythonPackages
      {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (pyFinal: _: (convertDerivationToOverlay pyFinal pythonOverlayDrvs))
        ];
      }
    //
      # Backwards compatibility with unnamespaced access to python packages
      mapAttrs' (
        keyWithSuffix: _:
        let
          key = removeSuffix "_drv" keyWithSuffix;
        in
        nameValuePair key (
          nixProtoWarn
            "Accessing ${key} directly is deperacted use python3Packages.${key}. Specific python package sets are also supported e.g. python310Packages"
            final.python3Packages.${key}
        )
      ) pythonOverlayDrvs;

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
  generateOverlay' =
    { drv, name }:
    let
      protoOverlayComponent = evaluateProtoDerivation drv;
    in
    composeManyExtensions [
      # Contains the package used to propagate proto dependencies
      (final: _: { ${name} = protoOverlayComponent final; })
      # Contains the language specific packages
      (createLanguageOverlay name protoOverlayComponent)
    ];
}
