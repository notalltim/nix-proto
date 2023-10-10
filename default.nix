{ lib
, std
, filter
}: rec {
  common = {
    toProtocInclude = x: lib.lists.fold (a: b: "-I=" + toString (a.src) + " " + b) "" x;
  };

  proto_lib = std // lib // common;

  generateMeta = { name, dir, version, protoDeps }:
    {
      name = name;
      src = filter {
        root = dir;
        include = [
          name
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
      python = (import ./python) { inherit meta; inherit proto_lib; };
    in
    python.proto_package;

  generateGRPCPython = { meta }:
    let
      python = (import ./python) { inherit meta; inherit proto_lib; };
    in
    python.grpc_package;

  generateDerivations = { meta }: rec {
    ${meta.name + "_proto_" + "drv"} = generateProto { inherit meta; };
    ${meta.name + "_proto_" + "py_drv"} = generatePython { inherit meta; };
    ${meta.name + "_proto_" + "grpc_py_drv"} = generateGRPCPython { inherit meta; };
  };

  generateOverlay = { meta }:
    let
      derivations = generateDerivations { inherit meta; };
      inherit (lib.attrsets) mapAttrs' nameValuePair;
    in
    final: prev: (mapAttrs' (key: value: nameValuePair (lib.strings.removeSuffix "_drv" key) (prev.callPackage value { })) derivations);

  generateOverlays = { metas }:
    let
      inherit (lib.lists) forEach;
    in
    forEach metas (meta: (generateOverlay { inherit meta; }));
}
