#ifndef GTRT_PROCEDURAL_MESH_INCLUDED
#define GTRT_PROCEDURAL_MESH_INCLUDED

//ref: SRP
float2 GetFullScreenTriangleTexCoord(uint vertexID)
{
    //get uv
#if UNITY_UV_STARTS_AT_TOP
    return float2((vertexID << 1) & 2, 1.0 - (vertexID & 2));
#else
    return float2((vertexID << 1) & 2, vertexID & 2);
#endif
}

float4 GetFullScreenTriangleVertexPosition(uint vertexID, float z = 0.0)
{
    //get vertices clip space pos
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    return float4(uv * 2.0 - 1.0, z, 1.0);
}

struct ProcTriVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

ProcTriVaryings ProcTriangleVertex(uint vertexID : SV_VertexID)
{
    ProcTriVaryings output = (ProcTriVaryings)0;
    output.positionCS = GetFullScreenTriangleVertexPosition(vertexID);
    output.uv = GetFullScreenTriangleTexCoord(vertexID);
    return output;
}

#endif