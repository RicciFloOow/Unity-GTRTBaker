//ref: https://github.com/boksajak/referencePT/blob/master/shaders/PathTracer.hlsl
#ifndef GTRT_REFERENCEPT_PATHTRACER_INCLUDE
#define GTRT_REFERENCEPT_PATHTRACER_INCLUDE

#include "referencePTShared.hlsl"
#include "referencePTBRDF.hlsl"

struct Attributes
{
    float2 uv;
};

struct VertexAttributes
{
    float3 position;
    float3 shadingNormal;
    float3 geometryNormal;
    float3 tangentWS;
    float3 bitangentWS;
    float2 uv;
};

struct IntersectionVertex
{
    float3 positionWS;
    float3 normalWS;
    float2 texCoord0;
};

RWTexture2D<float4> rw_accumulationBuffer;

RaytracingAccelerationStructure _SceneBVH;

SamplerState sampler_LinearRepeat;

// -------------------------------------------------------------------------
//    Defines
// -------------------------------------------------------------------------

#define FLT_MAX 3.402823466e+38F

// Defines after how many bounces will be the Russian Roulette applied
#define MIN_BOUNCES 3

// Switches between two RNGs
#define USE_PCG 1

// Number of candidates used for resampling of analytical lights
#define RIS_CANDIDATES_LIGHTS 8

// Enable this to cast shadow rays for each candidate during resampling. This is expensive but increases quality
#define SHADOW_RAY_IN_RIS 0

 // -------------------------------------------------------------------------
 //    RNG
 // -------------------------------------------------------------------------

#if USE_PCG
    #define RngStateType uint4
#else
    #define RngStateType uint
#endif

// PCG random numbers generator
// Source: "Hash Functions for GPU Rendering" by Jarzynski & Olano
uint4 pcg4d(uint4 v)
{
    v = v * 1664525u + 1013904223u;

    v.x += v.y * v.w; 
    v.y += v.z * v.x; 
    v.z += v.x * v.y; 
    v.w += v.y * v.z;

    v = v ^ (v >> 16u);

    v.x += v.y * v.w; 
    v.y += v.z * v.x; 
    v.z += v.x * v.y; 
    v.w += v.y * v.z;

    return v;
}

// 32-bit Xorshift random number generator
uint xorshift(inout uint rngState)
{
    rngState ^= rngState << 13;
    rngState ^= rngState >> 17;
    rngState ^= rngState << 5;
    return rngState;
}

// Jenkins's "one at a time" hash function
uint jenkinsHash(uint x) {
    x += x << 10;
    x ^= x >> 6;
    x += x << 3;
    x ^= x >> 11;
    x += x << 15;
    return x;
}

// Converts unsigned integer into float int range <0; 1) by using 23 most significant bits for mantissa
float uintToFloat(uint x) {
    return asfloat(0x3f800000 | (x >> 9)) - 1.0f;
}

#if USE_PCG

// Initialize RNG for given pixel, and frame number (PCG version)
RngStateType initRNG(uint2 pixelCoords, uint2 resolution, uint frameNumber) {
    return RngStateType(pixelCoords.xy, frameNumber, 0); //< Seed for PCG uses a sequential sample number in 4th channel, which increments on every RNG call and starts from 0
}

// Return random float in <0; 1) range  (PCG version)
float rand(inout RngStateType rngState) {
    rngState.w++; //< Increment sample index
    return uintToFloat(pcg4d(rngState).x);
}

#else

// Initialize RNG for given pixel, and frame number (Xorshift-based version)
RngStateType initRNG(uint2 pixelCoords, uint2 resolution, uint frameNumber) {
    RngStateType seed = dot(pixelCoords, uint2(1, resolution.x)) ^ jenkinsHash(frameNumber);
    return jenkinsHash(seed);
}

// Return random float in <0; 1) range (Xorshift-based version)
float rand(inout RngStateType rngState) {
    return uintToFloat(xorshift(rngState));
}

#endif

// Maps integers to colors using the hash function (generates pseudo-random colors)
float3 hashAndColor(int i) {
    uint hash = jenkinsHash(i);
    float r = ((hash >> 0) & 0xFF) / 255.0f;
    float g = ((hash >> 8) & 0xFF) / 255.0f;
    float b = ((hash >> 16) & 0xFF) / 255.0f;
    return float3(r, g, b);
}

// -------------------------------------------------------------------------
//    Utilities
// -------------------------------------------------------------------------

// Clever offset_ray function from Ray Tracing Gems chapter 6
// Offsets the ray origin from current position p, along normal n (which must be geometric normal)
// so that no self-intersection can occur.
float3 offsetRay(const float3 p, const float3 n)
{
    static const float origin = 1.0f / 32.0f;
    static const float float_scale = 1.0f / 65536.0f;
    static const float int_scale = 256.0f;

    int3 of_i = int3(int_scale * n.x, int_scale * n.y, int_scale * n.z);

    float3 p_i = float3(
        asfloat(asint(p.x) + ((p.x < 0) ? -of_i.x : of_i.x)),
        asfloat(asint(p.y) + ((p.y < 0) ? -of_i.y : of_i.y)),
        asfloat(asint(p.z) + ((p.z < 0) ? -of_i.z : of_i.z)));

    return float3(abs(p.x) < origin ? p.x + float_scale * n.x : p_i.x,
        abs(p.y) < origin ? p.y + float_scale * n.y : p_i.y,
        abs(p.z) < origin ? p.z + float_scale * n.z : p_i.z);
}

// Calculates probability of selecting BRDF (specular or diffuse) using the approximate Fresnel term
float getBrdfProbability(MaterialProperties material, float3 V, float3 shadingNormal) {
    
    // Evaluate Fresnel term using the shading normal
    // Note: we use the shading normal instead of the microfacet normal (half-vector) for Fresnel term here. That's suboptimal for rough surfaces at grazing angles, but half-vector is yet unknown at this point
    float specularF0 = luminance(baseColorToSpecularF0(material.baseColor, material.metalness));
    float diffuseReflectance = luminance(baseColorToDiffuseReflectance(material.baseColor, material.metalness));
    float Fresnel = saturate(luminance(evalFresnel(specularF0, shadowedF90(specularF0), max(0.0f, dot(V, shadingNormal)))));

    // Approximate relative contribution of BRDFs using the Fresnel term
    float specular = Fresnel;
    float diffuse = diffuseReflectance * (1.0f - Fresnel); //< If diffuse term is weighted by Fresnel, apply it here as well

    // Return probability of selecting specular BRDF over diffuse BRDF
    float p = (specular / max(0.0001f, (specular + diffuse)));

    // Clamp probability to avoid undersampling of less prominent BRDF
    return clamp(p, 0.1f, 0.9f);
}

// Helpers to convert between linear and sRGB color spaces
float3 linearToSrgb(float3 linearColor)
{
    return float3(linearToSrgb(linearColor.x), linearToSrgb(linearColor.y), linearToSrgb(linearColor.z));
}

float3 srgbToLinear(float3 srgbColor)
{
    return float3(srgbToLinear(srgbColor.x), srgbToLinear(srgbColor.y), srgbToLinear(srgbColor.z));
}

// Helpers for octahedron encoding of normals
float2 octWrap(float2 v)
{
    return float2((1.0f - abs(v.y)) * (v.x >= 0.0f ? 1.0f : -1.0f), (1.0f - abs(v.x)) * (v.y >= 0.0f ? 1.0f : -1.0f));
}

float2 encodeNormalOctahedron(float3 n)
{
    float2 p = float2(n.x, n.y) * (1.0f / (abs(n.x) + abs(n.y) + abs(n.z)));
    p = (n.z < 0.0f) ? octWrap(p) : p;
    return p;
}

float3 decodeNormalOctahedron(float2 p)
{
    float3 n = float3(p.x, p.y, 1.0f - abs(p.x) - abs(p.y));
    float2 tmp = (n.z < 0.0f) ? octWrap(float2(n.x, n.y)) : float2(n.x, n.y);
    n.x = tmp.x;
    n.y = tmp.y;
    return normalize(n);
}

float4 encodeNormals(float3 geometryNormal, float3 shadingNormal) {
    return float4(encodeNormalOctahedron(geometryNormal), encodeNormalOctahedron(shadingNormal));
}

void decodeNormals(float4 encodedNormals, out float3 geometryNormal, out float3 shadingNormal) {
    geometryNormal = decodeNormalOctahedron(encodedNormals.xy);
    shadingNormal = decodeNormalOctahedron(encodedNormals.zw);
}

// -------------------------------------------------------------------------
//    Lights & Shadows
// -------------------------------------------------------------------------

// Returns intensity of given light at specified distance
float3 getLightIntensityAtPoint(Light light, float distance) {
    if (light.type == POINT_LIGHT) {
        
#if 0
        // This is version with simple attenuation by inverse square root of distance
        return light.intensity / (distance * distance); 
#else
        // Cem Yuksel's improved attenuation avoiding singularity at distance=0
        // Source: http://www.cemyuksel.com/research/pointlightattenuation/
        const float radius = 0.5f; //< We hardcode radius at 0.5, but this should be a light parameter
        const float radiusSquared = radius * radius;
        const float distanceSquared = distance * distance;
        const float attenuation = 2.0f / (distanceSquared + radiusSquared + distance * sqrt(distanceSquared + radiusSquared));

        return light.intensity * attenuation;
#endif

    } else if (light.type == DIRECTIONAL_LIGHT) {
        return light.intensity;
    } else {
        return float3(1.0f, 0.0f, 1.0f);
    }
}

// Decodes light vector and distance from Light structure based on the light type
void getLightData(Light light, float3 hitPosition, out float3 lightVector, out float lightDistance) {
    if (light.type == POINT_LIGHT) {
        lightVector = (light.position - _CameraPos.xyz) - hitPosition;
        lightDistance = length(lightVector);
    } else if (light.type == DIRECTIONAL_LIGHT) {
        lightVector = light.position; //< We use position field to store direction for directional light
        lightDistance = FLT_MAX;
    } else {
        lightDistance = FLT_MAX;
        lightVector = float3(0.0f, 1.0f, 0.0f);
    }
}

// Casts a shadow ray and returns true if light is unoccluded
// Note that we use dedicated hit group with simpler shaders for shadow rays
bool castShadowRay(float3 hitPosition, float3 surfaceNormal, float3 directionToLight, float TMax)
{
    RayDesc ray;
    ray.Origin = offsetRay(hitPosition, surfaceNormal);
    ray.Direction = directionToLight;
    ray.TMin = 0.0f;
    ray.TMax = TMax;

    HitInfo payload;
    payload.hasHit = true; //< Initialize hit flag to true, it will be set to false on a miss

    // Trace the ray
    TraceRay(
        _SceneBVH,
        RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
        0xFF,
        0,
        1,
        1,
        ray,
        payload);

    return !payload.hasHit;
}

//走我们的灯光逻辑
bool getChunkLightData(float3 hitPosition, out uint startIndex, out uint localLightCount) {
    float3 localPos = hitPosition - _SceneBoundsMin;
    int3 chunk3D = int3(localPos / _LightChunkSize);
    chunk3D = clamp(chunk3D, int3(0, 0, 0), int3(_Subdivisions) - 1);
    
    int chunk1D = chunk3D.x + 
                  chunk3D.y * _Subdivisions.x + 
                  chunk3D.z * (_Subdivisions.x * _Subdivisions.y);
                  
    int2 offsetAndCount = _ChunkOffsetsBuffer[chunk1D];
    startIndex = offsetAndCount.x;
    localLightCount = offsetAndCount.y;
    
    return localLightCount > 0;
}

bool sampleLightUniformChunk(inout RngStateType rngState, uint startIndex, uint localLightCount, out Light light, out float lightSampleWeight) {
    uint randomIdx = min(localLightCount - 1, uint(rand(rngState) * localLightCount));
    uint globalLightIndex = _FlattenedLightIndicesBuffer[startIndex + randomIdx];
    light = _LightDatasBuffer[globalLightIndex];
    lightSampleWeight = float(localLightCount);
    return true;
}

// Samples a random light from the pool of all lights using RIS (Resampled Importance Sampling)
bool sampleLightRIS(inout RngStateType rngState, float3 hitPosition, float3 surfaceNormal, out Light selectedSample, out float lightSampleWeight) {
    
    selectedSample = (Light)0;
    lightSampleWeight = 0;
    uint startIndex, localLightCount;
    if (!getChunkLightData(hitPosition, startIndex, localLightCount)) {
        return false;
    }

    float totalWeights = 0.0f;
    float samplePdfG = 0.0f;

    for (int i = 0; i < RIS_CANDIDATES_LIGHTS; i++) {

        float candidateWeight;
        Light candidate;
        if (sampleLightUniformChunk(rngState, startIndex, localLightCount, candidate, candidateWeight)) {

            float3	lightVector;
            float lightDistance;
            getLightData(candidate, hitPosition, lightVector, lightDistance);

            // Ignore backfacing light
            float3 L = normalize(lightVector);
            if (dot(surfaceNormal, L) < 0.00001f) continue;

#if SHADOW_RAY_IN_RIS
            // Casting a shadow ray for all candidates here is expensive, but can significantly decrease noise
            if (!castShadowRay(hitPosition, surfaceNormal, L, lightDistance)) continue;
#endif

            float candidatePdfG = luminance(getLightIntensityAtPoint(candidate, length(lightVector)));
            const float candidateRISWeight = candidatePdfG * candidateWeight;

            totalWeights += candidateRISWeight;
            if (rand(rngState) < (candidateRISWeight / totalWeights)) {
                selectedSample = candidate;
                samplePdfG = candidatePdfG;
            }
        }
    }

    if (totalWeights == 0.0f) {
        return false;
    } else {
        lightSampleWeight = (totalWeights / float(RIS_CANDIDATES_LIGHTS)) / samplePdfG;
        return true;
    }
}

// -------------------------------------------------------------------------
//    Materials
// -------------------------------------------------------------------------
#include "UnityRaytracingMeshUtils.cginc"

#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
    float3 positionOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
    float3 normalOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
    outVertex.positionWS = mul(ObjectToWorld3x4(), float4(positionOS, 1)).xyz;
    outVertex.normalWS = normalize(mul(normalOS, (float3x3)WorldToObject3x4()));
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
    float2 texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
    
    float3 edge1 = v1.positionWS - v0.positionWS;
    float3 edge2 = v2.positionWS - v0.positionWS;
    
    VertexAttributes outVertex;
    outVertex.position = positionWS;
    outVertex.shadingNormal = normalWS;
    outVertex.geometryNormal = normalize(cross(edge1, edge2));
    outVertex.uv = texCoord0;

    float2 deltaUV1 = v1.texCoord0 - v0.texCoord0;
    float2 deltaUV2 = v2.texCoord0 - v0.texCoord0;
    
    float det = (deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x);
    
    float3 faceTangent = float3(1.0f, 0.0f, 0.0f);
    
    if (abs(det) > 1e-6f)
    {
        float invDet = 1.0f / det;
        faceTangent = (edge1 * deltaUV2.y - edge2 * deltaUV1.y) * invDet;
    }
    else
    {
        float3 up = abs(normalWS.z) < 0.999f ? float3(0.0f, 0.0f, 1.0f) : float3(1.0f, 0.0f, 0.0f);
        faceTangent = cross(up, normalWS);
    }
    
    outVertex.tangentWS = normalize(faceTangent - normalWS * dot(normalWS, faceTangent));
    outVertex.bitangentWS = normalize(cross(normalWS, outVertex.tangentWS));
    
    if (det < 0.0f) 
    {
        outVertex.bitangentWS = -outVertex.bitangentWS;
    }
    
    return outVertex;
}

bool testOpacityAnyHit(Attributes attrib, float alphaCutoff, Texture2D tex) 
{
    VertexAttributes vertex = GetVertexAttributes(attrib);
    
    float alpha = tex.SampleLevel(sampler_LinearRepeat, vertex.uv, 0.0f).w;
    
    return alpha < alphaCutoff;
}

// -------------------------------------------------------------------------
//    Camera
// -------------------------------------------------------------------------

// Generates a primary ray for pixel given in NDC space using pinhole camera
RayDesc generatePinholeCameraRay(float2 pixel)
{
    // Setup the ray
    RayDesc ray;
    ray.Origin = 0;
    ray.TMin = 0.f;
    ray.TMax = FLT_MAX;

    // Extract the aspect ratio and field of view from the projection matrix
    float aspect = _CameraProjMatrix[1][1] / _CameraProjMatrix[0][0];
    float tanHalfFovY = 1.0f / _CameraProjMatrix[1][1];

    float3 viewDirection = float3(pixel.x * aspect * tanHalfFovY, -pixel.y * tanHalfFovY, 1.0f);
    ray.Direction = normalize(mul((float3x3)_InvCameraViewMatrix, viewDirection));
    return ray;
}

// Helper to generate aperture samples of the thin lens model
float2 getApertureSample(inout RngStateType rngState)
{
    // Generate a sample within a circular aperture. Other shapes can be implemented here
    // Using just. xy coordinates of hemisphere sample gives samples within a disk
    return sampleHemisphere(float2(rand(rngState), rand(rngState))).xy;
}

// Generates a primary ray for pixel given in NDC space using thin lens model (with depth of field)
RayDesc generateThinLensCameraRay(float2 pixel, inout RngStateType rngState)
{
    // First find the point in distance at which we want perfect focus 
    RayDesc ray = generatePinholeCameraRay(pixel);
    float3 focalPoint = ray.Origin + ray.Direction * _FocusDistance;

    // Sample the aperture shape
    float2 apertureSample = getApertureSample(rngState) * _ApertureSize;

    // Jitter the ray origin within camera plane using aperture sample
    float3 rightVector = float3(_InvCameraViewMatrix._m00, _InvCameraViewMatrix._m10, _InvCameraViewMatrix._m20);
    float3 upVector = float3(_InvCameraViewMatrix._m01, _InvCameraViewMatrix._m11, _InvCameraViewMatrix._m21);
    ray.Origin = ray.Origin + rightVector * apertureSample.x + upVector * apertureSample.y;

    // Set ray direction from jittered origin towards the focal point
    ray.Direction = normalize(focalPoint - ray.Origin);

    return ray;
}

// Generates primary ray either using pinhole camera (for zero-sized apertures) or thin lens model
RayDesc generatePrimaryRay(float2 posNdcXy, inout RngStateType rngState)
{
    if (_ApertureSize == 0.0f)
        return generatePinholeCameraRay(posNdcXy);
    else
        return generateThinLensCameraRay(posNdcXy, rngState);
}

// -------------------------------------------------------------------------
//    Sky
// -------------------------------------------------------------------------

float3 loadSkyValue(float3 rayDirection) {

    // Load the sky value for given direction here, e.g. from environment map, procedural sky, etc.
    // Make sure to only account for sun once - either on the skybox or as an analytical light (if sun is included as explicit directional light, it shouldn't be on the skybox)
    return _SkyIntensity;
}

#endif