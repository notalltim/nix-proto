{ lib }: rec {

  mkProtoDerivation = in_set: { stdenvNoCC }: stdenvNoCC.mkDerivation (in_set // {
    version = if in_set ? version then in_set.version else "0.0.0";
    propagatedBuildInputs = in_set.protoDeps;
    installPhase = ''
      runHook preInstall
      cp -r . $out
      runHook postInstall
    '';
    #TODO(notalltim): Add user generation options
    # - allow user to control language specific naming through suffix
    # - allow the user to specify a install namespace that does not match source
  });

  generateOverlays' = drv_set:
    let
      inherit (lib.attrsets) mapAttrs' nameValuePair;
    in
    mapAttrs' (name: drv: nameValuePair (name + "_overlay") (__generateOverlay' { inherit drv; inherit name; })) drv_set;

  # Proto derivation (Deprecated)
  __generateProto = ((import ./proto) { inherit lib; }).package;
  # Python Generation
  __pythonGenerators = (import ./python) { inherit lib; };
  __generatePython = __pythonGenerators.gen_protobuf;
  __generateGRPCPython = __pythonGenerators.gen_grpc;
  # Cpp Generation
  __cppGenerators = (import ./cpp) { inherit lib; };
  __generateCpp = __cppGenerators.gen_protobuf;
  __generateGRPCCpp = __cppGenerators.gen_grpc;

  generateDerivations = { name }: rec {
    ${name + "_proto_" + "drv"} = __generateProto;
    ${name + "_proto_" + "py_drv"} = __generatePython;
    ${name + "_grpc_" + "py_drv"} = __generateGRPCPython;
    ${name + "_proto_" + "cpp_drv"} = __generateCpp;
    ${name + "_grpc_" + "cpp_drv"} = __generateGRPCCpp;
  };

  __evaluateProtoDerivation = input:
    let
      inherit (lib.trivial) functionArgs;
      doubleCall = !((functionArgs input) ? stdenvNoCC); # Check if the user passed a function or if this is the internal derivation
    in
    if doubleCall then prev: (prev.callPackage (prev.callPackage input { }) { }) else prev: (prev.callPackage input { });

  __generateOverlay' = { drv, name }:
    let
      inherit (lib.attrsets) mapAttrs' nameValuePair;
      inherit (lib.strings) removeSuffix;
      package = __evaluateProtoDerivation drv;
      derivations = (generateDerivations { inherit name; });
    in
    final: prev: (mapAttrs' (key: value: nameValuePair (removeSuffix "_drv" key) (prev.callPackage value { __proto_internal_meta_package = package prev; })) derivations)
      // rec { ${name} = package prev; };
}
