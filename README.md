# nix-proto

The nix-proto library provides automatic overlay generation and dependency management of code generated from proto files.

## Supported Releases

![release-22.05](https://github.com/notalltim/nix-proto/actions/workflows/release-22.05.yml/badge.svg) ![release-22.11](https://github.com/notalltim/nix-proto/actions/workflows/release-22.11.yml/badge.svg) ![release-23.05](https://github.com/notalltim/nix-proto/actions/workflows/release-23.05.yml/badge.svg) ![release-23.11](https://github.com/notalltim/nix-proto/actions/workflows/release-23.11.yml/badge.svg) ![unstable](https://github.com/notalltim/nix-proto/actions/workflows/unstable.yml/badge.svg) ![master](https://github.com/notalltim/nix-proto/actions/workflows/master.yml/badge.svg)

## Supported Cross Compile

**NOTE** only tested with `x86_64-linux` as the `buildPlatform`

![aarch64-multiplatform](https://github.com/notalltim/nix-proto/actions/workflows/aarch64-multiplatform/badge.svg) ![armv7-hf-multiplatform](https://github.com/notalltim/nix-proto/actions/workflows/armv7-hf-multiplatform/badge.svg)

## Features

### Code Generation

The overlay contains a set of derivations for the each generated code type. The supported types at the moment are (base_name is the name given to the `mkProtoDerivation` function):

- python protobuf (`base_name_proto_py`)
- python grpc (`base_name_grpc_py`)
- cpp protobuf (`base_name_proto_cpp`)
- cpp grpc (`base_name_grpc_cpp`)

Support should be easy to add for more targets by adding new derivations matching the style of the cpp or python derivations (see ./cpp/default.nix and ./python/default.nix)

### Dependency Management

The example [below](#usage) shows how to take a dependency on another set of protos dependencies can be transitive and will be propagated without additional user intervention except ensuring that all overlays are applied.

Code generation dependencies are managed on a per language basis i.e. if there are `test_apis` that depend on `base_apis` it `test_apis_proto_py` will only propagate a dependency on `base_api_proto_py` not `base_api` directly.

### Utilities

There are a few utilities provides to help using the `mkProtoDerivation` . They can be found under `nix-proto.lib`

- `overlayToList` - convert the overlay returned from the `generateOverlays'` call to a list
- `srcFromNamespace` - given a folder structure for a proto filter the given root to allow for multiple apis to be co-located
- `nameFromNamespace` - given a folder structure for a proto e.g. "./test/v1" create a name "test_v1"

## Usage

The interface is similar to `mkDerivation` with a few tweaks. The user creates derivations in the context of the `generateOverlays'` function.
**NOTE** there is a limitation that requires the name given to the attribute set to be the same as the name given to the derivation e.g. `base_api == base_api`.

### Generation

```nix
{
  overlays = nix-proto.generateOverlays' {
    base_api = nix-proto.mkProtoDerivation {
      name = "base_api";
      version = "1.0.1";
      src = ./proto;
    };

    test_api = { base_api } : nix-proto.mkProtoDerivation {
      name = "test_api";
      version = "1.2.3";
      src = ./test/proto;
      protoDeps = [base_api];
    };
  }
}
```

### Overlay

The structure of the returned overlay is an attribute set of overlays with names given in the initial set appended with "\_overlay".

```nix
{
  overlays = {
    base_api_overlay =  final: prev: {...};
    test_api_overlay =  final: prev: {...};
  };
}
```

### Flake Support

Using this library with flakes is simple just take it as an input. A simple example is shown below. Examples can be found [upstream-apis](https://github.com/notalltim/upstream-apis) and [test-apis](https://github.com/notalltim/test-apis).

```nix
{
  inputs =  {
    nix-proto = github:notalltim/nix-proto;
    nix-proto.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {nix-proto, ...}@inputs: let
    overlays = nix-proto.generateOverlays' {
      # ...
        base_api = nix-proto.mkProtoDerivation {
        }
      # ...
      };
    in
      { inherit overlays; } // flake-utils.lib.eachDefaultSystem (system: rec
      {
        legacyPackages = import nixpkgs { inherit system; overlays = nix-proto.lib.overlayToList overlays; };
      });
}
```
