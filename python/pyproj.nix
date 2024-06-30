{lib}: {
  name,
  version,
  dependencies,
  pythonVersion,
}: let
  toml = lib.serde.toTOML {
    project = {
      inherit name version dependencies;
      requires-python = ">=${pythonVersion}";
    };
    build-system = {
      requires = ["setuptools"];
      build-backend = "setuptools.build_meta";
    };
    tool.setuptools = {
      include-package-data = true;
      package-data."*" = ["*.pyi" "*.txt"];
    };
  };
in ''
  cat > pyproject.toml << EOF ${toml}
  EOF
  cat > setup.py << EOF
  from setuptools import setup
  setup()
  EOF
''
