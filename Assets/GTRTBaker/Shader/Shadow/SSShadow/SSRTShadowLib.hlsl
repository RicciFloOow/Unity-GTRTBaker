#ifndef GTRT_SS_RTSHADOW_LIB_INCLUDE
#define GTRT_SS_RTSHADOW_LIB_INCLUDE

uint _FrameIndex;

#ifdef UNITY_DXR
RaytracingAccelerationStructure _RTAccStruct;
#endif

Texture2D<float> _CamDepthTexture;
Texture2D<float4> _CamNormalsTexture;
Texture2D<float4> _CamMaterialsTexture;//w: smoothness
Texture2D<int2> _CamTopologyIDTexture;//x: instance id, y: primitive id
Texture2D<float> _HisCamDepthTexture;
Texture2D<int2> _HisCamTopologyIDTexture;
RWTexture2D<float> rw_OccludedRT;
RWTexture2D<float> rw_UnoccludedRT;
RWTexture2D<float4> rw_OutputRT;

struct Attributes
{
	float2 uv;
};

struct IntersectionVertex
{
	float2 texCoord0;
};

struct HitInfo 
{
    float hitEmission;
	bool isRayOcc;
};

#include "UnityRaytracingMeshUtils.cginc"

#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
    outVertex.texCoord0 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
}

#ifdef UNITY_DXR
IntersectionVertex GetVertexAttributes(Attributes attributeData)
{
	uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());
	
	IntersectionVertex v0, v1, v2;
    FetchIntersectionVertex(triangleIndices.x, v0);
    FetchIntersectionVertex(triangleIndices.y, v1);
    FetchIntersectionVertex(triangleIndices.z, v2);
	
    float3 barycentricCoordinates = float3(1.0 - attributeData.uv.x - attributeData.uv.y, attributeData.uv.x, attributeData.uv.y);

	float2 texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);

	IntersectionVertex outVertex;
	outVertex.texCoord0 = texCoord0;
	
	return outVertex;
}
#endif

#endif