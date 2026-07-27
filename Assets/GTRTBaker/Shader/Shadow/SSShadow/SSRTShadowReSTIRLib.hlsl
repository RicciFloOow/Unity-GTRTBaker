#ifndef GTRT_SS_RTSHADOW_RESTIR_LIB_INCLUDE
#define GTRT_SS_RTSHADOW_RESTIR_LIB_INCLUDE

#define GTRT_RESTIR_MAX_M 32

struct EmissionSample
{
    uint globalTriangleID;
    float2 barycentric;
};

struct SSRTShadowReservoir
{
    EmissionSample emiSample;
    float weightSum;     // W
    uint candidateCount; // M
    float targetAtSource;// temporal/spatial reuse
};

struct GlobalLightTriangle
{
    float3 v0;
    float3 v1;
    float3 v2;
    float3 normal;
    float emissionLuminance;
    float area;
    float samplingPMF;
};

struct AliasEntry
{
    float prob;
    uint aliasIndex;
};


uint _ScreenWidth;
uint _ScreenHeight;
float4 _HistoryTexSize;
uint _SpatialNeighborCount;
float _SpatialRadius;
uint _GlobalLightTriangleCount;

StructuredBuffer<GlobalLightTriangle> _GlobalLightTriangles;
StructuredBuffer<AliasEntry> _GlobalTriangleAliasTable;

StructuredBuffer<SSRTShadowReservoir> _TemporalReservoirs;
StructuredBuffer<SSRTShadowReservoir> _HistoryReservoirs;
RWStructuredBuffer<SSRTShadowReservoir> rw_TemporalReservoirs; 
RWStructuredBuffer<SSRTShadowReservoir> rw_CurrentReservoirs;

Texture2D<float4> _RayProposalTex;
Texture2D<float> _ResolveWeightTex;

RWTexture2D<float4> rw_RayProposalTex;
RWTexture2D<float> rw_ResolveWeightTex;

inline uint GetPixelIndex(uint2 pixelCoords)
{
    return pixelCoords.y * _ScreenWidth + pixelCoords.x;
}

inline SSRTShadowReservoir InitReservoir()
{
    SSRTShadowReservoir r;
    r.emiSample.globalTriangleID = 0xFFFFFFFF;
    r.emiSample.barycentric = float2(0, 0);
    r.weightSum = 0.0;
    r.candidateCount = 0;
    r.targetAtSource = 0.0;
    return r;
}

inline void UpdateReservoir(inout SSRTShadowReservoir r, EmissionSample s, float weight, float target, inout uint seed)
{
    if (weight <= 0.0 || target <= 0.0) 
        return;

    r.weightSum += weight;
    r.candidateCount += 1;
    
    if (pcgHash(seed) * r.weightSum <= weight)
    {
        r.emiSample = s;
        r.targetAtSource = target;
    }
}

inline void CombineReservoirs(inout SSRTShadowReservoir current, SSRTShadowReservoir other, float otherTargetAtCurrent, inout uint seed)
{
    if (other.candidateCount == 0 || otherTargetAtCurrent <= 0.0)
        return;
        
    float otherWeight = other.targetAtSource > 0.0 ? (other.weightSum * otherTargetAtCurrent / other.targetAtSource) : 0.0;
    
    current.weightSum += otherWeight;
    current.candidateCount += other.candidateCount;
    
    if (pcgHash(seed) * current.weightSum <= otherWeight)
    {
        current.emiSample = other.emiSample;
        current.targetAtSource = otherTargetAtCurrent;
    }
    
    if (current.candidateCount > GTRT_RESTIR_MAX_M)
    {
        float ratio = (float)GTRT_RESTIR_MAX_M / (float)current.candidateCount;
        current.weightSum *= ratio;
        current.candidateCount = GTRT_RESTIR_MAX_M;
    }
}

inline float3 InterpolatePosition(float3 v0, float3 v1, float3 v2, float2 barycentric)
{
    float u = barycentric.x;
    float v = barycentric.y;
    float w = 1.0 - u - v;
    return v0 * w + v1 * u + v2 * v;
}

inline float EvaluateUnshadowedTarget(EmissionSample emiSample, float3 receiverPos, float3 receiverNormal, float3 viewDir, float roughness, float specularProb)
{
    if (emiSample.globalTriangleID == 0xFFFFFFFF)
        return 0.0;

    GlobalLightTriangle tri = _GlobalLightTriangles[emiSample.globalTriangleID];
    
    float3 lightPos = InterpolatePosition(tri.v0 - _CameraPos.xyz, tri.v1 - _CameraPos.xyz, tri.v2 - _CameraPos.xyz, emiSample.barycentric);
    float3 L = lightPos - receiverPos;
    
    float distSq = dot(L, L);
    if (distSq < 1e-6) 
        return 0.0;

    float dist = sqrt(distSq);
    L /= dist;
    
    float cosTheta_e = dot(tri.normal, -L);
    if (cosTheta_e <= 0.0)
        return 0.0;

    float cosTheta_r = dot(receiverNormal, L);
    float NdotV = dot(receiverNormal, viewDir);

    if (cosTheta_r <= 0.0 || NdotV <= 0.0)
        return 0.0;

    float diffuseLobe = cosTheta_r * INV_PI;
    
    float3 H = normalize(viewDir + L);
    float NdotH = saturate(dot(receiverNormal, H));
    float VdotH = saturate(dot(viewDir, H));
    
    float a = max(0.001, roughness * roughness);
    float a2 = a * a;
    float d_ggx = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / max(1e-7, PI * d_ggx * d_ggx);
    
    float specularLobe = (D * NdotH) / max(4.0 * VdotH, 1e-4);
    
    float directionalPDF = lerp(diffuseLobe, specularLobe, specularProb);
    
    return tri.emissionLuminance * directionalPDF * cosTheta_e / max(distSq, 0.001);
}

inline EmissionSample GenerateInitialCandidate(inout uint seed)
{
    EmissionSample s = (EmissionSample)0;
    
    if (_GlobalLightTriangleCount == 0)
    {
        s.globalTriangleID = 0xFFFFFFFF;
        return s;
    }

    float rnd = pcgHash(seed);
    uint randIndex = min((uint)(pcgHash(seed) * _GlobalLightTriangleCount), _GlobalLightTriangleCount - 1);
    
    AliasEntry entry = _GlobalTriangleAliasTable[randIndex];
    s.globalTriangleID = (rnd < entry.prob) ? randIndex : entry.aliasIndex;

    float r1 = pcgHash(seed);
    float r2 = pcgHash(seed);
    float sqrt_r1 = sqrt(r1);
    s.barycentric = float2(1.0 - sqrt_r1, sqrt_r1 * (1.0 - r2));

    return s;
}

inline float GetEmissionSamplePDF(EmissionSample emiSample)
{
    if (emiSample.globalTriangleID == 0xFFFFFFFF) return 1.0;
    GlobalLightTriangle tri = _GlobalLightTriangles[emiSample.globalTriangleID];
    return tri.samplingPMF / max(tri.area, 1e-6);
}

inline void GetRayProposal(SSRTShadowReservoir r, float3 receiverPos, out float3 direction, out float TMax, out bool valid)
{
    if (r.emiSample.globalTriangleID == 0xFFFFFFFF || r.weightSum <= 0.0 || r.targetAtSource <= 0.0)
    {
        direction = float3(0, 1, 0);
        TMax = -1.0; 
        valid = false;
        return;
    }

    GlobalLightTriangle tri = _GlobalLightTriangles[r.emiSample.globalTriangleID];
    float3 lightPos = InterpolatePosition(tri.v0 - _CameraPos.xyz, tri.v1 - _CameraPos.xyz, tri.v2 - _CameraPos.xyz, r.emiSample.barycentric);
    
    float3 dir = lightPos - receiverPos;
    float dist = length(dir);
    
    if (dist < 1e-4)
    {
        direction = float3(0, 1, 0);
        TMax = -1.0;
        valid = false;
        return;
    }
    
    direction = dir / dist;
    TMax = dist - 1e-4;
    valid = true;
}

inline float GetReservoirResolveWeight(SSRTShadowReservoir r)
{
    if (r.candidateCount == 0) return 0.0;
    return r.weightSum / (float)r.candidateCount;
}


#endif