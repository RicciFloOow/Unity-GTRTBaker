#ifndef GTRT_LENS_DEPTH_OF_FIELD_LIB_INCLUDE
#define GTRT_LENS_DEPTH_OF_FIELD_LIB_INCLUDE

#include "../../Lib/BasicNoiseLib.hlsl"

float2 Rotate2D(float2 p, float angleRad)
{
    float cosVal, sinVal;
    sincos(angleRad, sinVal, cosVal);
    return float2(
        p.x * cosVal - p.y * sinVal,
        p.x * sinVal + p.y * cosVal
    );
}

float2 SampleApertureCircle(float2 xi, float radius, out float weight)//random pos xi in [0, 1)\times[0, 1)
{
    float2 p = (xi * 2.0 - 1.0) * radius;
    
    weight = (dot(p, p) <= radius * radius) ? 1.0 : 0.0;

    return p;
}

float2 SampleApertureDiamond(float2 xi, float radius, out float weight)
{
    float2 p = (xi * 2.0 - 1.0) * radius;

    weight = (abs(p.x) + abs(p.y) <= radius) ? 1.0 : 0.0;
    
    return p;
}

float2 SampleAperturePolygon(float2 xi, float radius, int numSides, float angleDeg, out float weight)
{
    float2 p = (xi * 2.0 - 1.0) * radius;
    
    float angleRad = angleDeg * (TWO_PI / 360.0);
    float2 pRot = Rotate2D(p, angleRad);
    
    float r = length(pRot);
    float theta = atan2(pRot.y, pRot.x);
    
    float sectorAngle = TWO_PI / float(numSides);
    float halfSector = sectorAngle * 0.5;
    
    float localTheta = fmod(theta, sectorAngle);
    if (localTheta < -halfSector) localTheta += sectorAngle;
    if (localTheta > halfSector) localTheta -= sectorAngle;
    
    float apothem = radius * cos(halfSector);
    float maxRAtTheta = apothem / cos(localTheta);
    
    weight = (r <= maxRAtTheta) ? 1.0 : 0.0;
    
    return p;
}

float2 SampleApertureMask(float2 xi, float radius, Texture2D<float> maskTex, SamplerState ss, out float weight)
{
    float2 p = (xi * 2.0 - 1.0) * radius;

    float2 uv = p / (2.0 * radius) + 0.5;
    
    if (any(uv < 0.0) || any(uv > 1.0))
    {
        weight = 0.0;
        return p;
    }
    
    weight = maskTex.SampleLevel(ss, uv, 0);
    
    return p;
}

RayDesc GenerateThinLensRayDesc(float3 pinholeOrigin, float3 pinholeDirection,
    float3 cameraForward, float3 cameraRight, float3 cameraUp,
    float focusDistance, float2 lensOffset, float anamorphicSqueeze,
    float tMin = 1e-5, float tMax = 1e6)
{
    RayDesc ray;
    ray.TMin = tMin;
    ray.TMax = tMax;
    
    if ((focusDistance <= 1e-4) || (dot(lensOffset, lensOffset) <= 1e-8))
    {
        ray.Origin = pinholeOrigin;
        ray.Direction = pinholeDirection;
        return ray;
    }
    
    float2 finalLensOffset = lensOffset;
    finalLensOffset.x *= anamorphicSqueeze;
    
    float hitT = focusDistance / dot(pinholeDirection, cameraForward);
    float3 focalPoint = pinholeOrigin + pinholeDirection * hitT;
    
    ray.Origin = pinholeOrigin + cameraRight * finalLensOffset.x + cameraUp * finalLensOffset.y;
    
    ray.Direction = normalize(focalPoint - ray.Origin);

    return ray;
}

#endif