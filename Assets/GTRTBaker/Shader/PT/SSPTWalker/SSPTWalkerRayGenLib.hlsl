#ifndef GTRT_SSPTWALKER_RAYGEN_LIB_INCLUDE
#define GTRT_SSPTWALKER_RAYGEN_LIB_INCLUDE

#include "../../Lens/DOF/LensDepthOfFieldLib.hlsl"
#include "../../Lib/OpenPBR/openpbr_lighting.hlsl"
#include "SSPTWalkerInputs.hlsl"

#define SSPT_MEDIUM_STACK_SIZE 4
#define SSPT_MISS_SKY 0
#define SSPT_MISS_VOLUME 1

float SSPT_GetRayTMin()
{
    return max(_RayTMin, 1e-5);
}

float SSPT_GetRayTMax()
{
    return max(_RayTMax, 1e5);
}

float SSPT_GetRayOffset()
{
    return max(_RayOffset, 1e-5);
}

uint SSPT_GetMinRussianRouletteBounce()
{
    return max(_MinRussianRouletteBounce, 3u);
}

uint SSPT_GetMaxNullHit()
{
    return max(_MaxNullHit, 32u);
}

float SSPT_Rand(inout uint seed)
{
    return pcgHash(seed);
}

float2 SSPT_Rand2(inout uint seed)
{
    return float2(SSPT_Rand(seed), SSPT_Rand(seed));
}

float3 SSPT_Rand3(inout uint seed)
{
    return float3(SSPT_Rand(seed), SSPT_Rand(seed), SSPT_Rand(seed));
}

OpenPBRPayload SSPT_MakeEmptyPayload()
{
    OpenPBRPayload payload = (OpenPBRPayload)0;
    payload.rayState = (uint)SSPT_RAY_STATE_NONE;
    payload.tHit = 0.0;
    return payload;
}

bool SSPT_PayloadHasHit(OpenPBRPayload payload)
{
    return (((uint)payload.rayState) & SSPT_RAY_STATE_HIT) != 0u;
}

bool SSPT_PayloadIsSkyMiss(OpenPBRPayload payload)
{
    return (((uint)payload.rayState) & SSPT_RAY_STATE_SKY_MISS) != 0u;
}

bool SSPT_PayloadIsVolumeMiss(OpenPBRPayload payload)
{
    return (((uint)payload.rayState) & SSPT_RAY_STATE_VOLUME_MISS) != 0u;
}

bool SSPT_VolumeHasDensity(OpenPBRVolumeProperties medium)
{
    return (medium.flags & (OPENPBR_VOLUME_ABSORBING | OPENPBR_VOLUME_SCATTERING)) != 0u;
}

float3 SSPT_SampleSky(float3 directionWS)
{
    return _SkyboxCubemap.SampleLevel(sampler_LinearClamp, directionWS, 0.0).xyz * _SkyboxIntensity;
}

float3 SSPT_OffsetRay(float3 positionWS, float3 normalWS)
{
    const float origin = 1.0 / 32.0;
    const float floatScale = 1.0 / 65536.0;
    const float intScale = 256.0;

    int3 of_i = int3(intScale * normalWS.x, intScale * normalWS.y, intScale * normalWS.z);
    float3 p_i = float3(
        asfloat(asint(positionWS.x) + ((positionWS.x < 0.0) ? -of_i.x : of_i.x)),
        asfloat(asint(positionWS.y) + ((positionWS.y < 0.0) ? -of_i.y : of_i.y)),
        asfloat(asint(positionWS.z) + ((positionWS.z < 0.0) ? -of_i.z : of_i.z)));

    return float3(
        abs(positionWS.x) < origin ? positionWS.x + floatScale * normalWS.x : p_i.x,
        abs(positionWS.y) < origin ? positionWS.y + floatScale * normalWS.y : p_i.y,
        abs(positionWS.z) < origin ? positionWS.z + floatScale * normalWS.z : p_i.z);
}

float3 SSPT_OffsetRayAlongDirection(float3 positionWS, float3 directionWS)
{
    return positionWS + directionWS * SSPT_GetRayOffset();
}

void SSPT_SetRay(inout RayDesc ray, float3 originWS, float3 directionWS, float tMax)
{
    ray.Origin = originWS;
    ray.Direction = OpenPBR_SafeNormalize(directionWS);
    ray.TMin = SSPT_GetRayTMin();
    ray.TMax = tMax;
}

float3 SSPT_SurfaceOffsetNormal(OpenPBRSurfaceCtx ctx, float3 wi)
{
    float3 geometryNormal = OpenPBR_SafeNormalize(ctx.geometry_normal);
    return dot(geometryNormal, wi) >= 0.0 ? geometryNormal : -geometryNormal;
}

bool SSPT_CrossedSurfaceBoundary(OpenPBRSurfaceCtx ctx, float3 wo, float3 wi)
{
    float3 geometryNormal = OpenPBR_SafeNormalize(ctx.geometry_normal);
    return dot(geometryNormal, wo) * dot(geometryNormal, wi) < -OPENPBR_EPSILON;
}

float3 SSPT_VolumeThroughputToBoundary(OpenPBRVolumeProperties medium, float distance)
{
    float3 transmittance = OpenPBR_EvaluateVolumeTransmittance(medium, distance);
    float pdf = OpenPBR_EvaluateVolumeDistancePdf(medium, distance, false);
    return transmittance / max(pdf, OPENPBR_EPSILON);
}

float3 SSPT_VolumeThroughputToScatter(OpenPBRVolumeProperties medium, OpenPBRVolumeDistanceSample sampleResult)
{
    return sampleResult.transmittance * medium.scattering / max(sampleResult.pdf, OPENPBR_EPSILON);
}

bool SSPT_TrySampleTIRFallback(OpenPBRMaterial material, OpenPBRSurfaceCtx ctx, float3 wo, float2 u, out float3 wi, out OpenPBRPathResult result)
{
    wi = float3(0.0, 0.0, 0.0);
    result = (OpenPBRPathResult)0;

    OpenPBRMaterial m = OpenPBR_SanitizeMaterial(material);
    if (ctx.geometry_thin_walled || m.transmission_weight <= OPENPBR_EPSILON || m.base_metalness >= 1.0)
    {
        return false;
    }

    float3 n = OpenPBR_SafeNormalize(ctx.shading_normal);
    float3 v = OpenPBR_SafeNormalize(wo);
    if (dot(n, v) < 0.0)
    {
        n = -n;
    }

    float3 t;
    float3 b;
    OpenPBR_BuildOrthonormalFrame(n, ctx.shading_tangent, t, b);

    float effectiveBaseRoughness = OpenPBR_CoatAffectedBaseRoughness(m.specular_roughness, m.coat_roughness, m.coat_weight);
    float2 alpha = OpenPBR_AnisotropicRoughness(effectiveBaseRoughness, m.specular_roughness_anisotropy);
    float3 h = OpenPBR_SampleGGXVNDF_Aniso(n, t, b, v, alpha, u);
    if (dot(h, v) < 0.0)
    {
        h = -h;
    }

    float etaRatio = OpenPBR_CoatedSpecularIORRatio(m.specular_ior, m.coat_ior, m.coat_weight, 1.0);
    float modulatedEta = OpenPBR_ModulatedIOR(etaRatio, m.specular_weight);
    float etaI = ctx.geometry_front_face ? 1.0 : modulatedEta;
    float etaT = ctx.geometry_front_face ? modulatedEta : 1.0;
    float3 refracted = refract(-v, h, etaI / max(etaT, OPENPBR_EPSILON));
    if (dot(refracted, refracted) > OPENPBR_EPSILON)
    {
        return false;
    }

    wi = OpenPBR_SafeNormalize(reflect(-v, h));
    result = OpenPBR_EvaluateSurface(m, ctx, wo, wi);
    return result.sample_pdf > OPENPBR_EPSILON && OpenPBR_Luminance(result.weighted_bsdf) > OPENPBR_EPSILON;
}

RayDesc GetThinLensCameraRay(uint2 pixelCoord, uint2 launchDim, uint frameIndex,
    float4x4 camProjMatrix, float4x4 invCamViewMatrix,
    uint lensMode, float apertureRadius, int apertureNumSides, float apertureAngle, float focusDistance, float anamorphicSqueeze,
    Texture2D<float> apertureMaskTex, SamplerState ss,
    inout uint pixelSeed, out float apertureWeight)
{
    float2 pixelScramble = pcgHash2D(pixelSeed);
    float2 lensScramble = pcgHash2D(pixelSeed);
    float2 pixelXi = GetScrambledR4Sequence(frameIndex, pixelScramble);
    float2 lensXi = GetScrambledR4Sequence(frameIndex + 66572828, lensScramble);

    float2 pixelCenter = float2(pixelCoord) + pixelXi;
    float2 ndc = pixelCenter / float2(launchDim.x, launchDim.y) * 2.0f - 1.0f;
    
    float aspect = camProjMatrix._m11 / camProjMatrix._m00;
    float tanHalfFovY = 1.0f / camProjMatrix._m11;
    
    float3 viewDirection = float3(ndc.x * aspect * tanHalfFovY, -ndc.y * tanHalfFovY, 1.0f);
    
    float3 pinholeDir = normalize(mul((float3x3)invCamViewMatrix, viewDirection));
    float3 cameraRight = float3(invCamViewMatrix._m00, invCamViewMatrix._m10, invCamViewMatrix._m20);
    float3 cameraUp = float3(invCamViewMatrix._m01, invCamViewMatrix._m11, invCamViewMatrix._m21);
    float3 cameraForward = float3(invCamViewMatrix._m02, invCamViewMatrix._m12, invCamViewMatrix._m22);
    
    float3 cameraOrigin = 0;
    
    apertureWeight = 1.0;
    float2 lensOffset = 0.0;
    
    if (lensMode == 1)
    {
        lensOffset = SampleApertureDiamond(lensXi, apertureRadius, apertureWeight);
    }
    else if (lensMode == 2)
    {
        lensOffset = SampleAperturePolygon(lensXi, apertureRadius, apertureNumSides, apertureAngle, apertureWeight);
    }
    else if (lensMode == 3)
    {
        lensOffset = SampleApertureMask(lensXi, apertureRadius, apertureMaskTex, ss, apertureWeight);
    }
    else 
    {
        lensOffset = SampleApertureCircle(lensXi, apertureRadius, apertureWeight);
    }
    
    RayDesc rayDoF = GenerateThinLensRayDesc(
        cameraOrigin, pinholeDir, 
        cameraForward, cameraRight, cameraUp, 
        focusDistance, lensOffset, anamorphicSqueeze
    );
    
    return rayDoF;
}

void SSPT_CommonMiss(inout OpenPBRPayload payload, float3 worldRayDirection)
{
    OpenPBRMaterial missMaterial = (OpenPBRMaterial)0;
    missMaterial.emission_luminance = 1.0;
    missMaterial.emission_color = SSPT_SampleSky(worldRayDirection);

    payload.rayState = (uint)SSPT_RAY_STATE_SKY_MISS;
    payload.material = PackOpenPBRMaterial(missMaterial);
}

void SSPT_VolumeMiss(inout OpenPBRPayload payload)
{
    payload.rayState = (uint)SSPT_RAY_STATE_VOLUME_MISS;
}

float3 SSPT_TracePath(RayDesc ray, inout uint pixelSeed, float3 initialThroughput)
{
    float3 radiance = 0.0;
    float3 throughput = initialThroughput;

    OpenPBRVolumeProperties mediumStack[SSPT_MEDIUM_STACK_SIZE];
    OpenPBRVolumeProperties currentMedium = OpenPBR_EmptyVolumeProperties(1.0);
    uint mediumDepth = 0u;
    uint nullHitCount = 0u;

    uint bounce = 0u;
    uint iteration = 0u;
    uint maxIteration = _MaxBounce + SSPT_GetMaxNullHit();

    [loop]
    while (bounce < _MaxBounce && iteration < maxIteration)
    {
        ++iteration;

        OpenPBRPayload payload = SSPT_MakeEmptyPayload();
        OpenPBRVolumeDistanceSample volumeSample = (OpenPBRVolumeDistanceSample)0;
        bool traceInMedium = SSPT_VolumeHasDensity(currentMedium);

        RayDesc traceRay = ray;
        if (traceInMedium)
        {
            volumeSample = OpenPBR_SampleVolumeDistance(currentMedium, SSPT_GetRayTMax(), SSPT_Rand2(pixelSeed));
            traceRay.TMax = volumeSample.distance;
            TraceRay(_RTAccStruct, RAY_FLAG_NONE, 0xFF, 0, 1, SSPT_MISS_VOLUME, traceRay, payload);
        }
        else
        {
            TraceRay(_RTAccStruct, RAY_FLAG_NONE, 0xFF, 0, 1, SSPT_MISS_SKY, traceRay, payload);
        }

        if (traceInMedium && SSPT_PayloadIsVolumeMiss(payload))
        {
            if (volumeSample.scattered)
            {
                throughput *= SSPT_VolumeThroughputToScatter(currentMedium, volumeSample);
                if (OpenPBR_Luminance(throughput) <= OPENPBR_EPSILON)
                {
                    break;
                }

                float3 scatterPosition = ray.Origin + ray.Direction * volumeSample.distance;
                OpenPBRPhaseSample phaseSample = OpenPBR_SampleVolumePhase(currentMedium, -ray.Direction, SSPT_Rand2(pixelSeed));
                throughput *= phaseSample.phase / max(phaseSample.sample_pdf, OPENPBR_EPSILON);
                SSPT_SetRay(ray, scatterPosition, phaseSample.wi, SSPT_GetRayTMax());
                nullHitCount = 0u;
                ++bounce;
                continue;
            }

            if (volumeSample.absorbed)
            {
                break;
            }

            break;
        }

        if (SSPT_PayloadIsSkyMiss(payload))
        {
            OpenPBRMaterial missMaterial = UnpackOpenPBRMaterial(payload.material);
            radiance += throughput * missMaterial.emission_luminance * missMaterial.emission_color;
            break;
        }

        if (!SSPT_PayloadHasHit(payload))
        {
            break;
        }

        float hitDistance = payload.tHit;
        float3 hitPosition = ray.Origin + ray.Direction * hitDistance;

        if (traceInMedium)
        {
            throughput *= SSPT_VolumeThroughputToBoundary(currentMedium, hitDistance);
            if (OpenPBR_Luminance(throughput) <= OPENPBR_EPSILON)
            {
                break;
            }
        }

        OpenPBRMaterial material = UnpackOpenPBRMaterial(payload.material);
        OpenPBRSurfaceCtx surfaceCtx = UnpackOpenPBRSurfaceContext(payload.surfaceCtx);

        if (surfaceCtx.geometry_opacity <= OPENPBR_EPSILON)
        {
            ++nullHitCount;
            if (nullHitCount > SSPT_GetMaxNullHit())
            {
                break;
            }

            SSPT_SetRay(ray, SSPT_OffsetRayAlongDirection(hitPosition, ray.Direction), ray.Direction, SSPT_GetRayTMax());
            continue;
        }

        nullHitCount = 0u;

        float3 wo = -ray.Direction;
        float3 wi;
        float3 surfaceU = SSPT_Rand3(pixelSeed);
        OpenPBRPathResult surfaceSample = OpenPBR_SampleSurface(material, surfaceCtx, wo, surfaceU, wi);
        radiance += throughput * surfaceSample.emission;

        if (surfaceSample.sample_pdf <= OPENPBR_EPSILON || OpenPBR_Luminance(surfaceSample.weighted_bsdf) <= OPENPBR_EPSILON)
        {
            OpenPBRPathResult tirSample;
            float3 tirWi;
            if (!SSPT_TrySampleTIRFallback(material, surfaceCtx, wo, surfaceU.xy, tirWi, tirSample))
            {
                break;
            }

            wi = tirWi;
            surfaceSample = tirSample;
        }

        bool sampledTransmission = (surfaceSample.event_flags & OPENPBR_EVENT_TRANSMISSION) != 0u;
        bool crossedBoundary = sampledTransmission && !surfaceCtx.geometry_thin_walled && SSPT_CrossedSurfaceBoundary(surfaceCtx, wo, wi);
        if (crossedBoundary)
        {
            if (surfaceCtx.geometry_front_face)
            {
                OpenPBRVolumeProperties surfaceMedium = OpenPBR_GetPayloadVolumeProperties(payload);
                if (OpenPBR_NormalizeVolumeSelector(OpenPBR_GetSurfaceVolumeSelector(payload.surfaceCtx)) != OPENPBR_VOLUME_NONE)
                {
                    if (mediumDepth < SSPT_MEDIUM_STACK_SIZE)
                    {
                        mediumStack[mediumDepth] = currentMedium;
                        ++mediumDepth;
                        currentMedium = surfaceMedium;
                    }
                }
            }
            else if (mediumDepth > 0u)
            {
                --mediumDepth;
                currentMedium = mediumStack[mediumDepth];
            }
            else
            {
                currentMedium = OpenPBR_EmptyVolumeProperties(1.0);
            }
        }

        throughput *= surfaceSample.weighted_bsdf / max(surfaceSample.sample_pdf, OPENPBR_EPSILON);

        if (bounce >= SSPT_GetMinRussianRouletteBounce())
        {
            float rrProbability = min(0.95, max(throughput.x, max(throughput.y, throughput.z)));
            if (SSPT_Rand(pixelSeed) > rrProbability)
            {
                break;
            }
            throughput /= max(rrProbability, OPENPBR_EPSILON);
        }

        float3 offsetNormal = SSPT_SurfaceOffsetNormal(surfaceCtx, wi);
        SSPT_SetRay(ray, SSPT_OffsetRay(hitPosition, offsetNormal), wi, SSPT_GetRayTMax());
        ++bounce;
    }

    return radiance;
}

void SSPT_StoreRadiance(uint2 pixelCoord, float3 radiance)
{
    float3 currentRadiance = radiance;
    if (_EnableAccumulation != 0u && _AccumulatedFrames > 1u)
    {
        float3 history = rw_OutputRT[pixelCoord].xyz;
        currentRadiance = history + (radiance - history) / float(_AccumulatedFrames);
    }

    rw_OutputRT[pixelCoord] = float4(currentRadiance, 1.0);
}

void SSPT_WalkPixel(uint2 pixelCoord, uint2 imageDim)
{
    uint pixelSeed = (pixelCoord.y * imageDim.x + pixelCoord.x) * 9781u + _FrameIndex * 6271u + 0x9e3779b9u;
    float apertureWeight;
    RayDesc ray = GetThinLensCameraRay(
        pixelCoord, imageDim, _FrameIndex,
        _CameraProjMatrix, _InvCameraViewMatrix,
        _LensMode, _ApertureRadius, _ApertureNumSides, _ApertureAngle, _FocusDistance, _AnamorphicSqueeze,
        _ApertureMaskTex, sampler_LinearClamp,
        pixelSeed, apertureWeight);
    ray.TMin = SSPT_GetRayTMin();
    ray.TMax = SSPT_GetRayTMax();

    float3 radiance = SSPT_TracePath(ray, pixelSeed, apertureWeight.xxx);
    SSPT_StoreRadiance(pixelCoord, radiance);
}




#endif
