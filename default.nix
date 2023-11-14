{ nix_lib
, std
, filter
}: rec {
  common = rec {
    inherit (lib.strings) splitString concatStringsSep;
    inherit (lib.lists) fold flatten concatMap unique;
    toProtocInclude = x: fold (a: b: "-I=" + toString (a.src) + " " + b) "" x;
    recursiveDeps = deps: concatMap (y: (if builtins.length y.protoDeps != 0 then [ (recursiveDeps y.protoDeps) ] else [ ]) ++ [ y ]) deps;
    recursiveProtoDeps = deps: unique ((flatten (recursiveDeps deps)));
    slashToUnderscore = namespace: concatStringsSep "_" (splitString "/" namespace);
  };

  lib = std // nix_lib // common;

  generateMeta = { name, dir, version, protoDeps, namespace ? "" }:
    {
      name = if namespace == "" then name else (lib.slashToUnderscore namespace) + "_" + name;
      src = filter {
        root = dir;
        include = [
          (if namespace == "" then name else namespace)
        ];
      };
      version = version;
      protoDeps = protoDeps;
    };

  generateProto = { meta }:
    let
      proto = (import ./proto) { inherit meta; inherit lib; };
    in
    proto.package;

  generatePython = { meta }:
    let
      python = (import ./python) { inherit meta; inherit lib; };
    in
    python.proto_package;

  generateGRPCPython = { meta }:
    let
      python = (import ./python) { inherit meta; inherit lib; };
    in
    python.grpc_package;

  generateCpp = { meta }:
    let
      cpp = (import ./cpp) { inherit meta; inherit lib; };
    in
    cpp.package_protobuf;

  generateGRPCCpp = { meta }:
    let
      cpp = (import ./cpp) { inherit meta; inherit lib; };
    in
    cpp.package_grpc;

  generateDerivations = { meta }: rec {
    ${meta.name + "_proto_" + "drv"} = generateProto { inherit meta; };
    ${meta.name + "_proto_" + "py_drv"} = generatePython { inherit meta; };
    ${meta.name + "_grpc_" + "py_drv"} = generateGRPCPython { inherit meta; };
    ${meta.name + "_proto_" + "cpp_drv"} = generateCpp { inherit meta; };
    ${meta.name + "_grpc_" + "cpp_drv"} = generateGRPCCpp { inherit meta; };
  };

  generateOverlay = { meta }:
    let
      derivations = generateDerivations { inherit meta; };
      inherit (lib.attrsets) mapAttrs' nameValuePair;
      inherit (lib.strings) removeSuffix;
    in
    final: prev: (mapAttrs' (key: value: nameValuePair (removeSuffix "_drv" key) (prev.callPackage value { })) derivations);

  generateOverlays = { metas }:
    let
      inherit (lib.lists) forEach;
    in
    forEach metas (meta: (generateOverlay { inherit meta; }));
}
