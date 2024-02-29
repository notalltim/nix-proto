{lib}: rec {
  inherit (lib.lists) forEach;
  inherit (lib) recursiveProtoDeps toProtocInclude loadMeta;

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
  toBuildDeps = deps: pkgs: forEach deps (dep: pkgs.${dep.name + "_proto_descriptor"});

  /*
  *
  Constructs a derivation to create the proto descriptors for a given folder of protos.

  # Type

  ```
  package :: { pkgs :: AttrSet, __proto_internal_meta_package :: Derivation } -> (AttrSet -> Derivation)
  ```

  - [pkgs] Package set that this derivation will be built into.
  - [__proto_internal_meta_package] The derivation holding the metadata and source location for the protos (dependencies etc.)
  */
  package = {
    pkgs,
    __proto_internal_meta_package,
    protobuf,
  }:
    pkgs.stdenvNoCC.mkDerivation rec {
      meta = loadMeta __proto_internal_meta_package;
      name = meta.name + "_proto_descriptor";
      src = meta.src;
      version = meta.version;
      nativeBuildInputs = [protobuf];
      propagatedBuildInputs = toBuildDeps meta.protoDeps pkgs;

      prePatch = ''
        for proto in `find "${meta.src}" -type f -name "*.proto"`; do
          # TODO: look into whether include imports is needed it is a bit heavy handed
          protoc  --include_imports \
                  --descriptor_set_out=$(realpath --relative-to="${meta.src}" "$proto" | sed 's/\.[^.]*$//g').desc \
                  ${(toProtocInclude ((recursiveProtoDeps meta.protoDeps) ++ [meta]))} $proto;
        done
      '';

      installPhase = ''
        shopt -s globstar
        runHook preInstall
        mkdir -p $out
        cp --parents -R ./**/*.desc $out
        runHook postInstall
      '';
    };
}
