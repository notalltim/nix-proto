{ std }:
{ name, version, dependencies }: std.serde.toTOML {
  project = {
    name = name;
    version = version;
    dependencies = dependencies;
    requires-python = ">=3.8";
  };
  build-system = {
    requires = [ "setuptools" ];
    build-backend = "setuptools.build_meta";
  };
}
