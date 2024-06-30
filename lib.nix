{
  lib,
  filter,
}: let
  inherit (lib.strings) splitString concatStringsSep;
  inherit (lib.lists) fold flatten concatMap unique;
  inherit (builtins) length;
  inherit (lib.attrsets) mapAttrsToList;

  /*
  * Common Internal functions used by the code generation
  */
  common = rec {
    /*
    *
    Convert a list of meta AttrSet to a string of include flags for protobuf

    # Example

    ```nix
      toProtoInclude [{ src = /store/path; } { src = /store/path2; } ] => "-I=/store/path -I=/store/path2";
    ```

    # Type

    ```type
    toProtoInclude :: List -> String
    ```
    # Arguments

    [meta_list]: List of meta attribute sets containing at minimum a `src` attribute
    */
    toProtocInclude = meta_list: fold (a: b: "-I=" + toString (a.src) + " " + b) "" meta_list;

    /*
    *
      Recursively walks the list of protoDeps and produces a list of lists containing the dependency tree of the protoDeps.
      This is the inner recursive function of `recursiveProtoDeps` which is used for protoc generation.

    # Example

    ```nix
      recursiveDeps [{ protoDeps = [dep1]; } { protoDeps = [dep1 dep2];} ] => [[dep1] [dep1 dep2]];
    ```

    # Type

    ```type
    recursiveDeps :: List -> List
    ```
    # Arguments

    [deps]: List of meta attribute sets containing at minimum a `protoDeps` attribute
    */
    recursiveDeps = deps:
      concatMap (y:
        (
          if length y.protoDeps != 0
          then [(recursiveDeps y.protoDeps)]
          else []
        )
        ++ [y])
      deps;

    /*
    *
      Takes the dependency tree produced by the `recursiveDeps` and flattens and de-duplicates the list

    # Example

    ```nix
      recursiveProtoDeps [{ protoDeps = [dep1]; } { protoDeps = [dep1 dep2];} ] => [dep1 dep2];
    ```

    # Type

    ```type
    recursiveProtoDeps :: List -> List
    ```
    # Arguments

    [deps]: List of meta attribute sets containing at minimum a `protoDeps` attribute
    */
    recursiveProtoDeps = deps: unique (flatten (recursiveDeps deps));

    /*
    *
    Convert a path (string delimited by '/') to a string delimited by '_'

    # Example

    ```nix
      slashToUnderscore "this/is/namespaced" => "this_is_namespaced";
    ```

    # Type

    ```type
    slashToUnderscore :: String -> String
    ```
    # Arguments

    [namespace]: string delimited by slashes ('/')
    */
    slashToUnderscore = namespace: concatStringsSep "_" (splitString "/" namespace);

    /*
    *
    Recursively define the meta attribute set using either the given meta in legacy mode aor the derivation in current mode.
    This function is likely to be replaced when legacy mode is removed

    # Example

    ```nix
      loadMeta {src = ./.; outPath = "..."; propagatedBuildInputs = [dep1]; } => { src = src; protoDeps [dep1] };
    ```

    # Type

    ```type
    loadMeta :: Derivation -> AttrSet
    ```
    # Arguments

    [drv]: derivation representing the metadata / store location of the protos being generated.
    */
    loadMeta = drv:
    # TODO(notalltim): remove when `generateMeta` is removed
      if drv ? proto_meta
      then drv.proto_meta
      else let
        deps = drv.propagatedBuildInputs;
        meta = {
          name = drv.name;
          version = drv.version;
          src = drv.outPath;
          protoDeps = concatMap (path: [(loadMeta path)]) deps;
        };
      in
        meta;

    nixProtoWarn = message: any: builtins.trace ("[1;31mnix-proto: " + message + "[0m") any;
  };

  /*
  * Public utilities for users of the nix-proto library
  */
  utilities = {
    /*
    *
     Filters the source at a root path given a namespace. useful for repos with multiple api libraries in a single repo.

    # Example

    ```nix
      srcFromNamespace {root = ./proto; namespace = "this/is/namespaced"; } => /nix/store/...;
    ```

    # Type

    ```type
    srcFromNamespace :: {root :: Path, namespace :: String  } -> Path
    ```

    - [root]: Root path to do the filtering from
    - [namespace]: Namespace of the proto being generated ( folder structure)

    - [returns] Source path filtered based on namespace

    */
    srcFromNamespace = {
      root,
      namespace,
    }:
      filter {
        inherit root;
        include = [
          namespace
        ];
      };

    /*
    *
    Turn namespace used for source filtering into a name for the package.

    # Example

    ```nix
    nameFromNamespace [{ protoDeps = [dep1]; } { protoDeps = [dep1 dep2];} ] => [dep1 dep2];
    ```

    # Type

    ```type
    nameFromNamespace :: String -> String
    ```
    # Arguments

    [namespace]: Namespace of the proto being generated ( folder structure)
    */
    nameFromNamespace = namespace: common.slashToUnderscore namespace;

    /*
    *
    Convert an attribute set of overlays to a list so that it can be used in a `legacyPackages` call;

    # Example

    ```nix
      overlayToList { overlay_1 = final: prev: ...; overlay_2 = final: prev: ...; } => [ overlay_1 overlay_2 ]
    ```

    # Type

    ```type
    overlayToList :: AttrSet -> List
    ```
    # Arguments

    [overlay_set]: attribute set of overlays.
    */
    overlayToList = overlay_set: mapAttrsToList (_: overlay: overlay) overlay_set;
  };
in {
  inherit common utilities;
}
