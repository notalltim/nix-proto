{ lib
, filter
}:
let
  inherit (lib.strings) splitString concatStringsSep;
  inherit (lib.lists) fold flatten concatMap unique;
  inherit (builtins) length;
  inherit (lib.attrsets) mapAttrsToList;

  common = rec {
    toProtocInclude = x: fold (a: b: "-I=" + toString (a.src) + " " + b) "" x;
    recursiveDeps = deps: concatMap (y: (if length y.protoDeps != 0 then [ (recursiveDeps y.protoDeps) ] else [ ]) ++ [ y ]) deps;
    recursiveProtoDeps = deps: unique ((flatten (recursiveDeps deps)));
    slashToUnderscore = namespace: concatStringsSep "_" (splitString "/" namespace);

    tryLoadMeta = storePath:
      # TODO(notalltim): remove when `generateMeta` is removed
      if storePath ? proto_meta then storePath.proto_meta else
      let
        deps = storePath.propagatedBuildInputs;
        meta = {
          name = storePath.name;
          version = storePath.version;
          src = storePath.outPath;
          protoDeps = concatMap (path: [ (tryLoadMeta path) ]) deps;
        };
      in
      meta;
  };

  utilities = {
    srcFromNamespace = { root, namespace }: filter {
      inherit root;
      include = [
        namespace
      ];
    };
    nameFromNamespace = namespace: common.slashToUnderscore namespace;
    overlayToList = overlay_set: mapAttrsToList (name: overlay: overlay) overlay_set;
  };
in
{
  inherit common utilities;
}
