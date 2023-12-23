{ lib }: rec {
  inherit (lib.lists) forEach;
  toBuildDeps = x: pkgs: forEach x (dep: pkgs.${dep.name + "_proto"});

  package = { stdenvNoCC, pkgs, __proto_internal_meta_package }: stdenvNoCC.mkDerivation rec {
    meta = (lib.tryLoadMeta __proto_internal_meta_package);
    name = meta.name + "_proto";
    src = meta.src;
    version = meta.version;

    propagatedBuildInputs = toBuildDeps meta.protoDeps pkgs;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/$name
      cp -r . $out/$name
      runHook post Install
    '';
  };
}
