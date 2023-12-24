{ nix_lib
, std
, filter
}:
let

  internal_lib = import ./lib.nix { inherit filter; lib = nix_lib; };
  inherit (internal_lib) utilities;

  # Internal lib used by code generation and nix generation
  lib = std // nix_lib // internal_lib.common;

  # Generation functions
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
