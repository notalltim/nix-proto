import grpc
from upstream_proto_py.upstream.v1.service.test_service_pb2 import Request, Response
from upstream_grpc_py.upstream.v1.service.test_service_pb2_grpc import TestServiceStub

channel: grpc.Channel = grpc.insecure_channel("localhost:50051")
stub = TestServiceStub(channel)
request = Request(id=1)
response: Response = stub.GetResponse(request)
_id: int = response.id
