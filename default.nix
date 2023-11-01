{ lib
, std
, filter
}: rec {
  common = rec {
    toProtocInclude = x: lib.lists.fold (a: b: "-I=" + toString (a.src) + " " + b) "" x;
    recursiveDeps = deps: proto_lib.lists.concatMap (y: (if builtins.length y.protoDeps != 0 then [ (recursiveDeps y.protoDeps) ] else [ ]) ++ [ y ]) deps;
    recursiveProtoDeps = deps: proto_lib.lists.unique ((proto_lib.lists.flatten (recursiveDeps deps)));
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

  generateCpp = { meta }:
    let
      cpp = (import ./cpp) { inherit meta; inherit proto_lib; };
    in
    cpp.package_protobuf;

  generateGRPCCpp = { meta }:
    let
      cpp = (import ./cpp) { inherit meta; inherit proto_lib; };
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
    in
    final: prev: (mapAttrs' (key: value: nameValuePair (lib.strings.removeSuffix "_drv" key) (prev.callPackage value { })) derivations);

  generateOverlays = { metas }:
    let
      inherit (lib.lists) forEach;
    in
    forEach metas (meta: (generateOverlay { inherit meta; }));
}
