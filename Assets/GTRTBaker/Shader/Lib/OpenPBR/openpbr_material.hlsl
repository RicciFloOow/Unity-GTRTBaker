//DXR中, payload用16bit类型会导致闪退(因此只能手动拼), 查到一个类似的结果 https://forums.developer.nvidia.com/t/driver-fails-when-creating-dxr-state-object-with-16bit-float-in-payload/304117
#ifndef GTRT_OPENPBR_MATERIAL_LIB_INCLUDE
#define GTRT_OPENPBR_MATERIAL_LIB_INCLUDE

#include "../Packing.hlsl"
#include "openpbr_common.hlsl"

struct OpenPBRMaterial
{
    float base_weight;
    float3 base_color;
    float base_metalness;
    float base_diffuse_roughness;
    //
    float specular_weight;
    float3 specular_color;
    float specular_roughness;
    float specular_roughness_anisotropy;
    float specular_ior;
    //
    float transmission_weight;
    float3 transmission_color;
    float transmission_depth;
    float3 transmission_scatter;
    float transmission_scatter_anisotropy;
    float transmission_dispersion_scale;
    float transmission_dispersion_abbe_number;
    //
    float subsurface_weight;
    float3 subsurface_color;
    float subsurface_radius;
    float3 subsurface_radius_scale;
    float subsurface_scatter_anisotropy;
    //
    float coat_weight;
    float3 coat_color;
    float coat_roughness;
    float coat_roughness_anisotropy;
    float coat_ior;
    float coat_darkening;
    //
    float fuzz_weight;
    float3 fuzz_color;
    float fuzz_roughness;
    //
    float emission_luminance;
    float3 emission_color;
    //
    float thin_film_weight;
    float thin_film_thickness;
    float thin_film_ior;
};

struct OpenPBRSurfaceCtx
{
    float geometry_opacity;//不用anyhit单独处理了, chs中直接记录到这里
    bool geometry_thin_walled;
    bool geometry_front_face;//HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE
    uint state_flags;
    float3 geometry_normal;//几何法线(三角形的法线)
    float3 shading_normal;
    float3 shading_tangent;
    float3 shading_coat_normal;
    float3 shading_coat_tangent;
};

uint OpenPBR_PackHalf2(float x, float y)
{
    return (f32tof16(x) & 0xffffu) | ((f32tof16(y) & 0xffffu) << 16);
}

float2 OpenPBR_UnpackHalf2(uint packedValue)
{
    return float2(f16tof32(packedValue & 0xffffu), f16tof32(packedValue >> 16));
}

uint OpenPBR_PackHalf1(float x)
{
    return f32tof16(x) & 0xffffu;
}

float OpenPBR_UnpackHalf1(uint packedValue)
{
    return f16tof32(packedValue & 0xffffu);
}

uint OpenPBR_PackUint16Half(uint lowValue, float highValue)
{
    return (lowValue & 0xffffu) | ((f32tof16(highValue) & 0xffffu) << 16);
}

uint OpenPBR_UnpackUint16(uint packedValue)
{
    return packedValue & 0xffffu;
}

float OpenPBR_UnpackHighHalf(uint packedValue)
{
    return f16tof32(packedValue >> 16);
}

uint OpenPBR_SetPackedUint16(uint packedValue, uint lowValue)
{
    return (packedValue & 0xffff0000u) | (lowValue & 0xffffu);
}

struct PackedOpenPBRMaterial
{
    float transmission_depth;
    float subsurface_radius;
    float emission_luminance;
    float thin_film_thickness;

    uint base_weight_base_color_x;
    uint base_color_yz;
    uint base_metalness_base_diffuse_roughness;

    uint specular_weight_specular_color_x;
    uint specular_color_yz;
    uint specular_roughness_specular_roughness_anisotropy;
    uint specular_ior_transmission_weight;

    uint transmission_color_xy;
    uint transmission_color_z_transmission_scatter_x;
    uint transmission_scatter_yz;
    uint transmission_scatter_anisotropy_transmission_dispersion_scale;
    uint transmission_dispersion_abbe_number_subsurface_weight;

    uint subsurface_color_xy;
    uint subsurface_color_z_subsurface_radius_scale_x;
    uint subsurface_radius_scale_yz;
    uint subsurface_scatter_anisotropy_coat_weight;

    uint coat_color_xy;
    uint coat_color_z_coat_roughness;
    uint coat_roughness_anisotropy_coat_ior;
    uint coat_darkening_fuzz_weight;

    uint fuzz_color_xy;
    uint fuzz_color_z_fuzz_roughness;

    uint emission_color_xy;
    uint emission_color_z_thin_film_weight;
    uint thin_film_ior;
};

struct PackedOpenPBRSurfaceCtx
{
    uint packedGeoNormal;
    uint packedShdNormal;
    uint packedShdTangent;
    uint packedShdCoatNormal;
    uint packedShdCoatTangent;
    //low 16 bits: surface props; high 16 bits: geometry opacity as binary16 bits
    uint packedSurfaceProp_geometry_opacity;
};

struct OpenPBRPayload
{
    PackedOpenPBRMaterial material;
    //bit0 是否命中,
    uint rayState;
    float tHit;//RayTCurrent()
    PackedOpenPBRSurfaceCtx surfaceCtx;
};

PackedOpenPBRSurfaceCtx PackOpenPBRSurfaceContext(OpenPBRSurfaceCtx surfaceCtx)
{
    PackedOpenPBRSurfaceCtx pCtx = (PackedOpenPBRSurfaceCtx)0;
    pCtx.packedGeoNormal = EncodeDirOctahedronSnorm2(surfaceCtx.geometry_normal);
    pCtx.packedShdNormal = EncodeDirOctahedronSnorm2(surfaceCtx.shading_normal);
    pCtx.packedShdTangent = EncodeDirOctahedronSnorm2(surfaceCtx.shading_tangent);
    pCtx.packedShdCoatNormal = EncodeDirOctahedronSnorm2(surfaceCtx.shading_coat_normal);
    pCtx.packedShdCoatTangent = EncodeDirOctahedronSnorm2(surfaceCtx.shading_coat_tangent);
    uint surfaceProp = 0u;
    surfaceProp |= (surfaceCtx.geometry_thin_walled ? OPENPBR_SURFACE_PROP_THIN_WALLED : 0u);
    surfaceProp |= (surfaceCtx.geometry_front_face ? OPENPBR_SURFACE_PROP_FRONT_FACE : 0u);
    surfaceProp |= (surfaceCtx.state_flags & OPENPBR_SURFACE_PROP_STATE_MASK);
    pCtx.packedSurfaceProp_geometry_opacity = OpenPBR_PackUint16Half(surfaceProp, surfaceCtx.geometry_opacity);
    return pCtx;
}

OpenPBRSurfaceCtx UnpackOpenPBRSurfaceContext(PackedOpenPBRSurfaceCtx pCtx)
{
    OpenPBRSurfaceCtx surfaceCtx = (OpenPBRSurfaceCtx)0;
    uint surfaceProp = OpenPBR_UnpackUint16(pCtx.packedSurfaceProp_geometry_opacity);
    surfaceCtx.geometry_thin_walled = (surfaceProp & OPENPBR_SURFACE_PROP_THIN_WALLED) != 0u;
    surfaceCtx.geometry_front_face = (surfaceProp & OPENPBR_SURFACE_PROP_FRONT_FACE) != 0u;
    surfaceCtx.state_flags = surfaceProp & OPENPBR_SURFACE_PROP_STATE_MASK;
    surfaceCtx.geometry_opacity = OpenPBR_UnpackHighHalf(pCtx.packedSurfaceProp_geometry_opacity);
    surfaceCtx.geometry_normal = DecodeDirOctahedronSnorm2(pCtx.packedGeoNormal);
    surfaceCtx.shading_normal = DecodeDirOctahedronSnorm2(pCtx.packedShdNormal);
    surfaceCtx.shading_tangent = DecodeDirOctahedronSnorm2(pCtx.packedShdTangent);
    surfaceCtx.shading_coat_normal = DecodeDirOctahedronSnorm2(pCtx.packedShdCoatNormal);
    surfaceCtx.shading_coat_tangent = DecodeDirOctahedronSnorm2(pCtx.packedShdCoatTangent);
    return surfaceCtx;
}

uint OpenPBR_GetSurfaceStateFlags(PackedOpenPBRSurfaceCtx pCtx)
{
    return OpenPBR_UnpackUint16(pCtx.packedSurfaceProp_geometry_opacity) & OPENPBR_SURFACE_PROP_STATE_MASK;
}

uint OpenPBR_GetSurfaceVolumeSelector(PackedOpenPBRSurfaceCtx pCtx)
{
    return OpenPBR_UnpackUint16(pCtx.packedSurfaceProp_geometry_opacity) & OPENPBR_SURFACE_PROP_VOLUME_MASK;
}

PackedOpenPBRSurfaceCtx OpenPBR_SetSurfaceStateFlags(PackedOpenPBRSurfaceCtx pCtx, uint stateFlags)
{
    uint surfaceProp = OpenPBR_UnpackUint16(pCtx.packedSurfaceProp_geometry_opacity);
    surfaceProp = (surfaceProp & OPENPBR_SURFACE_PROP_FIXED_MASK) | (stateFlags & OPENPBR_SURFACE_PROP_STATE_MASK);
    pCtx.packedSurfaceProp_geometry_opacity = OpenPBR_SetPackedUint16(pCtx.packedSurfaceProp_geometry_opacity, surfaceProp);
    return pCtx;
}

PackedOpenPBRSurfaceCtx OpenPBR_SetSurfaceVolumeSelector(PackedOpenPBRSurfaceCtx pCtx, uint selectorFlags)
{
    uint surfaceProp = OpenPBR_UnpackUint16(pCtx.packedSurfaceProp_geometry_opacity);
    surfaceProp = (surfaceProp & ~OPENPBR_SURFACE_PROP_VOLUME_MASK) | (selectorFlags & OPENPBR_SURFACE_PROP_VOLUME_MASK);
    pCtx.packedSurfaceProp_geometry_opacity = OpenPBR_SetPackedUint16(pCtx.packedSurfaceProp_geometry_opacity, surfaceProp);
    return pCtx;
}

PackedOpenPBRMaterial PackOpenPBRMaterial(OpenPBRMaterial material)
{
    PackedOpenPBRMaterial pMat = (PackedOpenPBRMaterial)0;

    pMat.transmission_depth  = material.transmission_depth;
    pMat.subsurface_radius   = material.subsurface_radius;
    pMat.emission_luminance  = material.emission_luminance;
    pMat.thin_film_thickness = material.thin_film_thickness;
    
    pMat.base_weight_base_color_x = OpenPBR_PackHalf2(material.base_weight, material.base_color.x);
    pMat.base_color_yz = OpenPBR_PackHalf2(material.base_color.y, material.base_color.z);
    pMat.base_metalness_base_diffuse_roughness = OpenPBR_PackHalf2(material.base_metalness, material.base_diffuse_roughness);

    pMat.specular_weight_specular_color_x = OpenPBR_PackHalf2(material.specular_weight, material.specular_color.x);
    pMat.specular_color_yz = OpenPBR_PackHalf2(material.specular_color.y, material.specular_color.z);
    pMat.specular_roughness_specular_roughness_anisotropy = OpenPBR_PackHalf2(material.specular_roughness, material.specular_roughness_anisotropy);
    pMat.specular_ior_transmission_weight = OpenPBR_PackHalf2(material.specular_ior, material.transmission_weight);

    pMat.transmission_color_xy = OpenPBR_PackHalf2(material.transmission_color.x, material.transmission_color.y);
    pMat.transmission_color_z_transmission_scatter_x = OpenPBR_PackHalf2(material.transmission_color.z, material.transmission_scatter.x);
    pMat.transmission_scatter_yz = OpenPBR_PackHalf2(material.transmission_scatter.y, material.transmission_scatter.z);
    pMat.transmission_scatter_anisotropy_transmission_dispersion_scale = OpenPBR_PackHalf2(material.transmission_scatter_anisotropy, material.transmission_dispersion_scale);
    pMat.transmission_dispersion_abbe_number_subsurface_weight = OpenPBR_PackHalf2(material.transmission_dispersion_abbe_number, material.subsurface_weight);

    pMat.subsurface_color_xy = OpenPBR_PackHalf2(material.subsurface_color.x, material.subsurface_color.y);
    pMat.subsurface_color_z_subsurface_radius_scale_x = OpenPBR_PackHalf2(material.subsurface_color.z, material.subsurface_radius_scale.x);
    pMat.subsurface_radius_scale_yz = OpenPBR_PackHalf2(material.subsurface_radius_scale.y, material.subsurface_radius_scale.z);
    pMat.subsurface_scatter_anisotropy_coat_weight = OpenPBR_PackHalf2(material.subsurface_scatter_anisotropy, material.coat_weight);

    pMat.coat_color_xy = OpenPBR_PackHalf2(material.coat_color.x, material.coat_color.y);
    pMat.coat_color_z_coat_roughness = OpenPBR_PackHalf2(material.coat_color.z, material.coat_roughness);
    pMat.coat_roughness_anisotropy_coat_ior = OpenPBR_PackHalf2(material.coat_roughness_anisotropy, material.coat_ior);
    pMat.coat_darkening_fuzz_weight = OpenPBR_PackHalf2(material.coat_darkening, material.fuzz_weight);

    pMat.fuzz_color_xy = OpenPBR_PackHalf2(material.fuzz_color.x, material.fuzz_color.y);
    pMat.fuzz_color_z_fuzz_roughness = OpenPBR_PackHalf2(material.fuzz_color.z, material.fuzz_roughness);

    pMat.emission_color_xy = OpenPBR_PackHalf2(material.emission_color.x, material.emission_color.y);
    pMat.emission_color_z_thin_film_weight = OpenPBR_PackHalf2(material.emission_color.z, material.thin_film_weight);
    pMat.thin_film_ior = OpenPBR_PackHalf1(material.thin_film_ior);

    return pMat;
}

OpenPBRMaterial UnpackOpenPBRMaterial(PackedOpenPBRMaterial pMat)
{
    OpenPBRMaterial material = (OpenPBRMaterial)0;
    
    material.transmission_depth  = pMat.transmission_depth;
    material.subsurface_radius   = pMat.subsurface_radius;
    material.emission_luminance  = pMat.emission_luminance;
    material.thin_film_thickness = pMat.thin_film_thickness;
    
    float2 halfPair;

    halfPair = OpenPBR_UnpackHalf2(pMat.base_weight_base_color_x);
    material.base_weight = halfPair.x;
    material.base_color.x = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.base_color_yz);
    material.base_color.y = halfPair.x;
    material.base_color.z = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.base_metalness_base_diffuse_roughness);
    material.base_metalness = halfPair.x;
    material.base_diffuse_roughness = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.specular_weight_specular_color_x);
    material.specular_weight = halfPair.x;
    material.specular_color.x = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.specular_color_yz);
    material.specular_color.y = halfPair.x;
    material.specular_color.z = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.specular_roughness_specular_roughness_anisotropy);
    material.specular_roughness = halfPair.x;
    material.specular_roughness_anisotropy = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.specular_ior_transmission_weight);
    material.specular_ior = halfPair.x;
    material.transmission_weight = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.transmission_color_xy);
    material.transmission_color.x = halfPair.x;
    material.transmission_color.y = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.transmission_color_z_transmission_scatter_x);
    material.transmission_color.z = halfPair.x;
    material.transmission_scatter.x = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.transmission_scatter_yz);
    material.transmission_scatter.y = halfPair.x;
    material.transmission_scatter.z = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.transmission_scatter_anisotropy_transmission_dispersion_scale);
    material.transmission_scatter_anisotropy = halfPair.x;
    material.transmission_dispersion_scale = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.transmission_dispersion_abbe_number_subsurface_weight);
    material.transmission_dispersion_abbe_number = halfPair.x;
    material.subsurface_weight = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.subsurface_color_xy);
    material.subsurface_color.x = halfPair.x;
    material.subsurface_color.y = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.subsurface_color_z_subsurface_radius_scale_x);
    material.subsurface_color.z = halfPair.x;
    material.subsurface_radius_scale.x = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.subsurface_radius_scale_yz);
    material.subsurface_radius_scale.y = halfPair.x;
    material.subsurface_radius_scale.z = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.subsurface_scatter_anisotropy_coat_weight);
    material.subsurface_scatter_anisotropy = halfPair.x;
    material.coat_weight = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.coat_color_xy);
    material.coat_color.x = halfPair.x;
    material.coat_color.y = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.coat_color_z_coat_roughness);
    material.coat_color.z = halfPair.x;
    material.coat_roughness = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.coat_roughness_anisotropy_coat_ior);
    material.coat_roughness_anisotropy = halfPair.x;
    material.coat_ior = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.coat_darkening_fuzz_weight);
    material.coat_darkening = halfPair.x;
    material.fuzz_weight = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.fuzz_color_xy);
    material.fuzz_color.x = halfPair.x;
    material.fuzz_color.y = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.fuzz_color_z_fuzz_roughness);
    material.fuzz_color.z = halfPair.x;
    material.fuzz_roughness = halfPair.y;

    halfPair = OpenPBR_UnpackHalf2(pMat.emission_color_xy);
    material.emission_color.x = halfPair.x;
    material.emission_color.y = halfPair.y;
    halfPair = OpenPBR_UnpackHalf2(pMat.emission_color_z_thin_film_weight);
    material.emission_color.z = halfPair.x;
    material.thin_film_weight = halfPair.y;
    material.thin_film_ior = OpenPBR_UnpackHalf1(pMat.thin_film_ior);

    return material;
}

uint OpenPBR_NormalizeVolumeSelector(uint selectorFlags)
{
    selectorFlags &= OPENPBR_SURFACE_PROP_VOLUME_MASK;

    uint selectedCount = 0u;
    selectedCount += ((selectorFlags & OPENPBR_VOLUME_SUBSURFACE) != 0u) ? 1u : 0u;
    selectedCount += ((selectorFlags & OPENPBR_VOLUME_TRANSMISSION) != 0u) ? 1u : 0u;
    selectedCount += ((selectorFlags & OPENPBR_VOLUME_COAT) != 0u) ? 1u : 0u;

    return selectedCount == 1u ? selectorFlags : OPENPBR_VOLUME_NONE;
}

#endif
