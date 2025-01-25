{ lib }:
rec {
  inherit (lib.lists) forEach;
  inherit (lib) loadMeta;

  /*
    *
    Convert a set of attribute sets of metadata to a list of derivations looked up by name from the package set provided.

    # Type

    ```
    toBuildDeps :: List -> List
    ```

    - [deps] List of attribute sets minimally containing the name of the base proto.
    - [pkgs] List of attribute sets minimally containing the name of the base proto.

    - [returns] List of derivations from the package set that the python package depends on.
  */
  toBuildDeps = deps: pkgs: forEach deps (dep: pkgs.${dep.name + "_proto"});

  /*
    *
    **DEPRECATED** This function executes approximately the same thing as the meta derivations.
    Constructs a derivation to install the given protos in a specific folder in the outPath.

    # Type

    ```
    package :: { pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> (AttrSet -> Derivation)
    ```

    - [pkgs] Package set that this derivation will be built into.
    - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */
  package =
    { pkgs, __proto_internal_meta_package }:
    pkgs.stdenvNoCC.mkDerivation rec {
      meta = loadMeta __proto_internal_meta_package;
      name = meta.name + "_proto";
      src = meta.src;
      version = meta.version;

      propagatedBuildInputs = toBuildDeps meta.protoDeps pkgs;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/$name
        cp -r . $out/$name
        runHook postInstall
      '';
    };
}
