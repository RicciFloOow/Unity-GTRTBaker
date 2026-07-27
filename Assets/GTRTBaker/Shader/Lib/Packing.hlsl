#ifndef GTRT_PACKING_LIB_INCLUDED
#define GTRT_PACKING_LIB_INCLUDED

//ref: https://www.jcgt.org/published/0003/02/01/ P13
float2 SignNotZero(float2 v)
{
    return float2(v.x >= 0 ? 1 : -1, v.y >= 0 ? 1 : -1);
}

float2 ProbeDir2OctUV(float3 v)
{
    float2 p = v.xy * (1 / (abs(v.x) + abs(v.y) + abs(v.z)));
    float2 coord = v.z <= 0 ? (1 - abs(p.yx)) * SignNotZero(p) : p;
    return coord * 0.5 + 0.5;
}

float3 OctUV2ProbeDir(float2 e)
{
    e = e * 2 - 1;//maps to [-1,1]\times[-1,1]
    float3 v = float3(e.xy, 1 - abs(e.x) - abs(e.y));
    [flatten]
    if (v.z < 0)
    {
        v.xy = (1 - abs(v.yx)) * SignNotZero(v.xy);
    }
    return normalize(v);
}

//优化版本
float2 OctWrap(float2 v)
{
    return (1.0f - abs(v.yx)) * SignNotZero(v);
}

float2 EncodeDirOctahedron(float3 n)
{
    n /= dot(abs(n), 1.0f); 
    return n.z >= 0.0f ? n.xy : OctWrap(n.xy);
}

float3 DecodeDirOctahedron(float2 p)
{
    float3 n = float3(p.x, p.y, 1.0f - dot(abs(p), 1.0f));
    n.xy = n.z >= 0.0f ? n.xy : OctWrap(n.xy);
    return normalize(n);
}

uint EncodeDirOctahedronSnorm2(float3 n)
{
    float2 oct = EncodeDirOctahedron(n);
    int2 packed = int2(round(clamp(oct, -1.0f, 1.0f) * 32767.0f));
    return (asuint(packed.x) & 0xFFFF) | (asuint(packed.y) << 16);
}

float3 DecodeDirOctahedronSnorm2(uint p)
{
    int x = asint(p << 16) >> 16;
    int y = asint(p) >> 16;
    float2 uv = max(float2(x, y) / 32767.0f, -1.0f);
    return DecodeDirOctahedron(uv);
}

#endif