nix-proto:
let
  upstream = nix-proto.generateOverlays' {
    namespaced = nix-proto.mkProtoDerivation {
      name = "namespaced";
      src = nix-proto.srcFromNamespace {
        root = ./proto;
        namespace = "outer/inner/namespaced";
      };
      version = "1.0.0";
      protoDeps = [ ];
    };
    upstream =
      {
        namespaced,
        unnamespaced,
      }:
      nix-proto.mkProtoDerivation {
        name = "upstream";
        src = nix-proto.srcFromNamespace {
          root = ./proto;
          namespace = "upstream";
        };
        version = "1.0.0";
        protoDeps = [
          namespaced
          unnamespaced
        ];
      };
    unnamespaced = nix-proto.mkProtoDerivation {
      name = "unnamespaced";
      src = ./proto/unnamespaced;
      version = "0.0.0";
      protoDeps = [ ];
    };
  };

  user = nix-proto.generateOverlays' {
    middle =
      { upstream }:
      nix-proto.mkProtoDerivation {
        name = "middle";
        src = nix-proto.srcFromNamespace {
          root = ./proto;
          namespace = "middle";
        };
        version = "1.0.0";
        protoDeps = [ upstream ];
      };

    toplevel =
      {
        upstream,
        middle,
      }:
      nix-proto.mkProtoDerivation {
        name = "toplevel";
        src = nix-proto.srcFromNamespace {
          root = ./proto;
          namespace = "toplevel";
        };
        version = "1.0.0";
        protoDeps = [
          upstream
          middle
        ];
      };
  };
in
upstream // user
