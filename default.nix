{ nix_lib
, std
, filter
}:
let

  __internal_lib = import ./lib.nix { inherit filter; lib = nix_lib; };
  inherit (__internal_lib) utilities;

  lib = std // nix_lib // __internal_lib.common;

  generation = import ./generation.nix { inherit lib; };

  #TODO(notalltim): remove this when downstream not using it
  legacy = import ./legacy.nix { inherit filter; inherit lib; generateDerivations = generation.generateDerivations; };
in
{
  inherit (legacy) generateMeta generateOverlay generateOverlays;
  inherit (generation) mkProtoDerivation generateOverlays';
  lib = {
    inherit (utilities) srcFromNamespace nameFromNamespace overlayToList;
  };
}
