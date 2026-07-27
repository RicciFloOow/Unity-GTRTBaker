#ifndef GTRT_SSPTWALKER_MESH_LIB_INCLUDE
#define GTRT_SSPTWALKER_MESH_LIB_INCLUDE

#include "UnityRaytracingMeshUtils.cginc"

struct Attributes
{
    float2 uv;
};

struct VertexAttributes
{
    float3 position;
    float3 shadingNormal;
    float3 geometryNormal;
    float3 tangentWS;//shading tangent
    float3 bitangentWS;
    float2 uv;
};

struct IntersectionVertex
{
    float3 positionWS;
    float3 normalWS;
    float4 tangentWS;
    float2 texCoord0;
};

#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

float3 BuildFallbackTangent(float3 normalWS)
{
    float3 up = abs(normalWS.z) < 0.99999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    return normalize(cross(up, normalWS));
}

void BuildShadingTangentFrame(float3 normalWS, float4 interpolatedTangentWS, float3 edge1, float3 edge2, float2 deltaUV1, float2 deltaUV2, out float3 tangentWS, out float3 bitangentWS)
{
    float3 tangent = interpolatedTangentWS.xyz;
    tangent -= normalWS * dot(normalWS, tangent);
    float handedness = interpolatedTangentWS.w < 0.0 ? -1.0 : 1.0;

    if (dot(tangent, tangent) <= 1e-8)
    {
        float det = deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x;

        if (abs(det) > 1e-8)
        {
            tangent = edge1 * deltaUV2.y - edge2 * deltaUV1.y;
            float3 bitangentCandidate = -edge1 * deltaUV2.x + edge2 * deltaUV1.x;
            tangent -= normalWS * dot(normalWS, tangent);

            if (dot(tangent, tangent) > 1e-8)
            {
                float3 tangentNorm = normalize(tangent);
                handedness = dot(cross(normalWS, tangentNorm), bitangentCandidate) < 0.0 ? -1.0 : 1.0;
                tangent = tangentNorm;
            }
        }
    }

    if (dot(tangent, tangent) <= 1e-8)
    {
        tangent = BuildFallbackTangent(normalWS);
        handedness = 1.0;
    }
    else
    {
        tangent = normalize(tangent);
    }

    tangentWS = tangent;
    bitangentWS = normalize(cross(normalWS, tangentWS)) * handedness;
}

void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
    float3 positionOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
    float3 normalOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
    float4 tangentOS = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTangent);
    outVertex.positionWS = mul(ObjectToWorld3x4(), float4(positionOS, 1)).xyz;
    outVertex.normalWS = normalize(mul(normalOS, (float3x3)WorldToObject3x4()));
    outVertex.tangentWS = float4(mul((float3x3)ObjectToWorld3x4(), tangentOS.xyz), tangentOS.w);
    outVertex.texCoord0 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
}

VertexAttributes GetVertexAttributes(Attributes attributeData)
{
    uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());
    
    IntersectionVertex v0, v1, v2;
    FetchIntersectionVertex(triangleIndices.x, v0);
    FetchIntersectionVertex(triangleIndices.y, v1);
    FetchIntersectionVertex(triangleIndices.z, v2);
    
    float3 barycentricCoordinates = float3(1.0 - attributeData.uv.x - attributeData.uv.y, attributeData.uv.x, attributeData.uv.y);

    float3 positionWS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.positionWS, v1.positionWS, v2.positionWS, barycentricCoordinates);
    float3 normalWS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalWS, v1.normalWS, v2.normalWS, barycentricCoordinates);
    float4 tangentWS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangentWS, v1.tangentWS, v2.tangentWS, barycentricCoordinates);
    float2 texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
    
    float3 edge1 = v1.positionWS - v0.positionWS;
    float3 edge2 = v2.positionWS - v0.positionWS;
    float2 deltaUV1 = v1.texCoord0 - v0.texCoord0;
    float2 deltaUV2 = v2.texCoord0 - v0.texCoord0;
    
    VertexAttributes outVertex;
    outVertex.position = positionWS;
    outVertex.shadingNormal = normalize(normalWS);
    outVertex.geometryNormal = normalize(cross(edge1, edge2));
    BuildShadingTangentFrame(outVertex.shadingNormal, tangentWS, edge1, edge2, deltaUV1, deltaUV2, outVertex.tangentWS, outVertex.bitangentWS);
    outVertex.uv = texCoord0;
    
    return outVertex;
}

#endif
