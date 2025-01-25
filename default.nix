{
  nix_lib,
  std,
  filter,
}: let
  internal_lib = import ./lib.nix {
    inherit filter;
    lib = nix_lib;
  };
  inherit (internal_lib) utilities;

  # Internal lib used by code generation and nix generation
  lib = std // nix_lib // internal_lib.common // internal_lib.utilities;

  # Generation functions
  generation = import ./generation.nix {inherit lib;};
in {
  inherit (generation) mkProtoDerivation generateOverlays';
  inherit (utilities) srcFromNamespace nameFromNamespace overlayToList;
}
