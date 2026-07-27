#ifndef GTRT_OPENPBR_COMMON_LIB_INCLUDE
#define GTRT_OPENPBR_COMMON_LIB_INCLUDE

#define OPENPBR_PI 3.14159265358979323846
#define OPENPBR_INV_PI 0.31830988618379067154
#define OPENPBR_EPSILON 1e-6

#define OPENPBR_VOLUME_NONE         0u
#define OPENPBR_VOLUME_ABSORBING    1u
#define OPENPBR_VOLUME_SCATTERING   2u
#define OPENPBR_VOLUME_SUBSURFACE   4u
#define OPENPBR_VOLUME_TRANSMISSION 8u
#define OPENPBR_VOLUME_COAT         16u

#define OPENPBR_SURFACE_PROP_THIN_WALLED 0x0001u
#define OPENPBR_SURFACE_PROP_FRONT_FACE  0x0002u
#define OPENPBR_SURFACE_PROP_FIXED_MASK  0x0003u
#define OPENPBR_SURFACE_PROP_STATE_MASK  0xfffcu

#define OPENPBR_SURFACE_PROP_VOLUME_MASK (OPENPBR_VOLUME_SUBSURFACE | OPENPBR_VOLUME_TRANSMISSION | OPENPBR_VOLUME_COAT)

#define OPENPBR_EVENT_NONE         0u
#define OPENPBR_EVENT_REFLECTION   1u
#define OPENPBR_EVENT_TRANSMISSION 2u
#define OPENPBR_EVENT_DIFFUSE      4u
#define OPENPBR_EVENT_GLOSSY       8u
#define OPENPBR_EVENT_VOLUME       16u
#define OPENPBR_EVENT_EMISSION     32u
#define OPENPBR_EVENT_NULL         64u

float OpenPBR_Pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float OpenPBR_Pow6(float x)
{
    float x2 = x * x;
    return x2 * x2 * x2;
}

float3 OpenPBR_SafePositive(float3 value)
{
    return max(value, float3(OPENPBR_EPSILON, OPENPBR_EPSILON, OPENPBR_EPSILON));
}

float3 OpenPBR_SafeNormalize(float3 value)
{
    return value * rsqrt(max(dot(value, value), OPENPBR_EPSILON));
}

float OpenPBR_Luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

void OpenPBR_BuildOrthonormalFrame(float3 normalWS, float3 tangentWS, out float3 tangentOut, out float3 bitangentOut)
{
    float3 n = OpenPBR_SafeNormalize(normalWS);
    float3 t = tangentWS - n * dot(tangentWS, n);

    if (dot(t, t) < OPENPBR_EPSILON)
    {
        float3 up = abs(n.z) < 0.999999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
        t = cross(up, n);
    }

    tangentOut = OpenPBR_SafeNormalize(t);
    bitangentOut = OpenPBR_SafeNormalize(cross(n, tangentOut));
}

float3 OpenPBR_ToLocal(float3 value, float3 normalWS, float3 tangentWS, float3 bitangentWS)
{
    return float3(dot(value, tangentWS), dot(value, bitangentWS), dot(value, normalWS));
}

#endif