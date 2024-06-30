from functools import cache
from importlib.resources import files
from pathlib import Path
from typing import List

from google.protobuf.descriptor_pb2 import (FileDescriptorProto,
                                            FileDescriptorSet)


@cache
def file_descriptor_set() -> List[FileDescriptorProto]:
    """Get List of protobuf file descriptors for the @package@ and dependencies"""
    file_descriptors = []
    with files("@package@").joinpath("descriptors.txt").open("r") as f:
        for line in f:
            for descriptor_file_set_path in Path(str(line)).rglob("*.desc"):
                with open(descriptor_file_set_path, "rb") as file_descriptor:
                    file_descriptor_set = FileDescriptorSet.FromString(
                        file_descriptor.read()
                    )
                    for descriptor in file_descriptor_set.file:
                        file_descriptors.append(descriptor)
    return file_descriptors
