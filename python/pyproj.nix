{lib}: {
  name,
  version,
  dependencies,
}:
lib.serde.toTOML {
  project = {
    name = name;
    version = version;
    dependencies = dependencies;
    requires-python = ">=3.8";
  };
  build-system = {
    requires = ["setuptools"];
    build-backend = "setuptools.build_meta";
  };
  tool.setuptools = {
    include-package-data = true;
    package-data."*" = ["*.pyi" "*.txt"];
  };
}
