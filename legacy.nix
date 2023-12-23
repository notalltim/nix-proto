{ lib
, filter
, generateDerivations
}: rec {
  #TODO(notalltim): remove when all down stream users are changed over
  generateMeta = { name ? "", dir, version, protoDeps, namespace ? "" }:
    lib.trivial.warn "generateMeta is deprecated and will be removed in the future please use mkProtoDerivation" {
      name = if namespace == "" then name else (lib.slashToUnderscore namespace);
      src = filter {
        root = dir;
        include = [
          (if namespace == "" then name else namespace)
        ];
      };
      version = version;
      protoDeps = protoDeps;
    };

  #TODO(notalltim): remove when `generateMeta` is removed
  __metaCompat = meta': { stdenvNoCC }: stdenvNoCC.mkDerivation meta' // {
    name = meta'.name;
    version = meta'.name;
    proto_meta = meta';
  };

  #TODO(notalltim): repurpose when `generateMeta` is removed
  generateOverlay = { meta }:
    let
      inherit (lib.attrsets) mapAttrs' nameValuePair;
      inherit (lib.strings) removeSuffix;
      package = prev: prev.callPackage (__metaCompat meta) {};
      derivations = lib.trivial.warn "generateOverlay is deprecated and will work differently in a future release please use mkProtoDerivation and generateOverlays'" (generateDerivations { name = meta.name; });
    in
    final: prev: (mapAttrs' (key: value: nameValuePair (removeSuffix "_drv" key) (prev.callPackage value { __proto_internal_meta_package = (package prev); })) derivations);

  #TODO(notalltim): remove when `generateMeta` is removed
  generateOverlays = { metas }:
    let
      inherit (lib.lists) forEach;
    in
    forEach metas (meta: (generateOverlay { inherit meta; }));
}
