{ meta, lib }: rec {

  toBuildDeps = x: pkgs: lib.lists.forEach x (dep: pkgs.${dep.name + "_proto"});

  package = { stdenvNoCC, pkgs }: stdenvNoCC.mkDerivation rec {
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
