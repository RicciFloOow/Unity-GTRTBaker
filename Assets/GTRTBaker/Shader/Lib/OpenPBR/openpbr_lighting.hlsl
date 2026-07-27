#ifndef GTRT_OPENPBR_LIGHTING_LIB_INCLUDE
#define GTRT_OPENPBR_LIGHTING_LIB_INCLUDE

#include "openpbr_material.hlsl"

#define OPENPBR_USE_THIN_FILM_APPROX 1

struct OpenPBRVolumeProperties
{
    float3 absorption;
    float3 scattering;
    float3 extinction;
    float3 single_scatter_albedo;
    float anisotropy;
    float ior;
    uint flags;
};

struct OpenPBRVolumeDistanceSample
{
    float distance;
    float3 transmittance;
    float pdf;
    bool scattered;
    bool absorbed;
    uint event_flags;
};

struct OpenPBRPhaseSample
{
    float3 wi;
    float phase;
    float sample_pdf;
    uint event_flags;
};

struct OpenPBRPathResult
{
    float3 bsdf;
    float3 weighted_bsdf;
    float3 emission;
    float3 continuation_weight;
    float sample_pdf;
    float eta;
    float opacity;
    uint event_flags;
};

OpenPBRMaterial OpenPBR_SanitizeMaterial(OpenPBRMaterial m)
{
    m.base_weight = saturate(m.base_weight);
    m.base_color = saturate(m.base_color);
    m.base_diffuse_roughness = saturate(m.base_diffuse_roughness);
    m.base_metalness = saturate(m.base_metalness);

    m.specular_weight = max(m.specular_weight, 0.0);
    m.specular_color = saturate(m.specular_color);
    m.specular_roughness = saturate(m.specular_roughness);
    m.specular_roughness_anisotropy = saturate(m.specular_roughness_anisotropy);
    m.specular_ior = max(m.specular_ior, OPENPBR_EPSILON);

    m.transmission_weight = saturate(m.transmission_weight);
    m.transmission_color = saturate(m.transmission_color);
    m.transmission_depth = max(m.transmission_depth, 0.0);
    m.transmission_scatter = saturate(m.transmission_scatter);
    m.transmission_scatter_anisotropy = clamp(m.transmission_scatter_anisotropy, -0.999, 0.999);
    m.transmission_dispersion_scale = saturate(m.transmission_dispersion_scale);
    m.transmission_dispersion_abbe_number = max(m.transmission_dispersion_abbe_number, OPENPBR_EPSILON);

    m.subsurface_weight = saturate(m.subsurface_weight);
    m.subsurface_color = saturate(m.subsurface_color);
    m.subsurface_radius = max(m.subsurface_radius, 0.0);
    m.subsurface_radius_scale = saturate(m.subsurface_radius_scale);
    m.subsurface_scatter_anisotropy = clamp(m.subsurface_scatter_anisotropy, -0.999, 0.999);

    m.fuzz_weight = saturate(m.fuzz_weight);
    m.fuzz_color = saturate(m.fuzz_color);
    m.fuzz_roughness = saturate(m.fuzz_roughness);

    m.coat_weight = saturate(m.coat_weight);
    m.coat_color = saturate(m.coat_color);
    m.coat_roughness = saturate(m.coat_roughness);
    m.coat_roughness_anisotropy = saturate(m.coat_roughness_anisotropy);
    m.coat_ior = max(m.coat_ior, OPENPBR_EPSILON);
    m.coat_darkening = saturate(m.coat_darkening);

    m.thin_film_weight = saturate(m.thin_film_weight);
    m.thin_film_thickness = max(m.thin_film_thickness, 0.0);
    m.thin_film_ior = max(m.thin_film_ior, OPENPBR_EPSILON);

    m.emission_luminance = max(m.emission_luminance, 0.0);
    m.emission_color = max(m.emission_color, float3(0.0, 0.0, 0.0));

    return m;
}

float OpenPBR_IORToF0(float eta)
{
    float e = (1.0 - eta) / max(1.0 + eta, OPENPBR_EPSILON);
    return e * e;
}

float OpenPBR_ModulatedIOR(float eta, float specularWeight)
{
    float f0 = OpenPBR_IORToF0(eta);
    float scaledF0 = clamp(specularWeight * f0, 0.0, 0.999999);
    float epsilon = sign(eta - 1.0) * sqrt(scaledF0);
    return (1.0 + epsilon) / max(1.0 - epsilon, OPENPBR_EPSILON);
}

float OpenPBR_CoatedSpecularIORRatio(float specularIOR, float coatIOR, float coatWeight, float ambientIOR)
{
    float nbOverNa = specularIOR / max(ambientIOR, OPENPBR_EPSILON);
    float nbOverNc = specularIOR / max(coatIOR, OPENPBR_EPSILON);
    float ncOverNb = coatIOR / max(specularIOR, OPENPBR_EPSILON);
    float tirFixed = nbOverNc > 1.0 ? nbOverNc : ncOverNb;
    return lerp(nbOverNa, tirFixed, saturate(coatWeight));
}

float OpenPBR_FresnelDielectric(float cosThetaI, float eta)
{
    float mu = saturate(cosThetaI);
    float sinThetaISq = max(0.0, 1.0 - mu * mu);
    float sinThetaTSq = sinThetaISq / max(eta * eta, OPENPBR_EPSILON);

    if (sinThetaTSq >= 1.0)
    {
        return 1.0;
    }

    float cosThetaT = sqrt(max(0.0, 1.0 - sinThetaTSq));
    float rsDenom = max(mu + eta * cosThetaT, OPENPBR_EPSILON);
    float rpDenom = max(eta * mu + cosThetaT, OPENPBR_EPSILON);
    float rs = (mu - eta * cosThetaT) / rsDenom;
    float rp = (eta * mu - cosThetaT) / rpDenom;
    return saturate(0.5 * (rs * rs + rp * rp));
}

float OpenPBR_AverageFresnelDielectricEtaGteOne(float eta)
{
    eta = max(eta, 1.0);

    if (eta <= 1.0 + OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float numerator = 10893.0 * eta - 1438.2;
    float denominator = -774.4 * eta * eta + 10212.0 * eta + 1.0;
    return saturate(log(max(numerator / max(denominator, OPENPBR_EPSILON), OPENPBR_EPSILON)));
}

float OpenPBR_AverageFresnelDielectric(float eta)
{
    eta = max(eta, OPENPBR_EPSILON);

    if (eta < 1.0)
    {
        float invEta = 1.0 / eta;
        float fInv = OpenPBR_AverageFresnelDielectricEtaGteOne(invEta);
        return saturate(1.0 - eta * eta * (1.0 - fInv));
    }

    return OpenPBR_AverageFresnelDielectricEtaGteOne(eta);
}

float3 OpenPBR_FresnelSchlick(float cosTheta, float3 f0)
{
    float fc = OpenPBR_Pow5(1.0 - saturate(cosTheta));
    return f0 + (float3(1.0, 1.0, 1.0) - f0) * fc;
}

float3 OpenPBR_FresnelMetalF82(float cosTheta, float3 f0, float3 edgeTint, float specularWeight)
{
    float mu = saturate(cosTheta);
    float muBar = 1.0 / 7.0;

    float3 fSchlick = OpenPBR_FresnelSchlick(mu, f0);
    float3 fSchlickBar = OpenPBR_FresnelSchlick(muBar, f0);
    float3 fTargetBar = saturate(edgeTint) * fSchlickBar;

    float correctionScale = (mu * OpenPBR_Pow6(1.0 - mu)) / max(muBar * OpenPBR_Pow6(1.0 - muBar), OPENPBR_EPSILON);
    float3 f82 = fSchlick - correctionScale * (fSchlickBar - fTargetBar);
    return saturate(specularWeight * max(f82, float3(0.0, 0.0, 0.0)));
}

float2 OpenPBR_AnisotropicRoughness(float roughness, float anisotropy)
{
    float r = saturate(roughness);
    float a = saturate(anisotropy);
    float invA = 1.0 - a;
    float alphaT = r * r * sqrt(2.0 / max(1.0 + invA * invA, OPENPBR_EPSILON));
    float alphaB = invA * alphaT;
    return max(float2(alphaT, alphaB), float2(0.001, 0.001));
}

float OpenPBR_CoatAffectedBaseRoughness(float baseRoughness, float coatRoughness, float coatWeight)
{
    float rb = saturate(baseRoughness);
    float rc = saturate(coatRoughness);
    float rb4 = rb * rb * rb * rb;
    float rc4 = rc * rc * rc * rc;
    float affected = pow(saturate(rb4 + 2.0 * rc4), 0.25);
    return lerp(rb, affected, saturate(coatWeight));
}

float OpenPBR_D_GGX_Aniso(float3 h, float3 n, float3 t, float3 b, float alphaT, float alphaB)
{
    float3 hl = OpenPBR_ToLocal(h, n, t, b);
    float ax = max(alphaT, 0.001);
    float ay = max(alphaB, 0.001);
    float denom = (hl.x * hl.x) / (ax * ax) + (hl.y * hl.y) / (ay * ay) + hl.z * hl.z;
    return 1.0 / max(OPENPBR_PI * ax * ay * denom * denom, OPENPBR_EPSILON);
}

float OpenPBR_Lambda_GGX_Aniso(float3 wLocal, float alphaT, float alphaB)
{
    float absZ = max(abs(wLocal.z), OPENPBR_EPSILON);
    float ax = max(alphaT, 0.001);
    float ay = max(alphaB, 0.001);
    float a2 = ax * ax * wLocal.x * wLocal.x + ay * ay * wLocal.y * wLocal.y;
    return 0.5 * (sqrt(1.0 + a2 / max(absZ * absZ, OPENPBR_EPSILON)) - 1.0);
}

float OpenPBR_G2_Smith_GGX_Aniso(float3 v, float3 l, float3 n, float3 t, float3 b, float alphaT, float alphaB)
{
    float3 vl = OpenPBR_ToLocal(v, n, t, b);
    float3 ll = OpenPBR_ToLocal(l, n, t, b);
    float lambdaV = OpenPBR_Lambda_GGX_Aniso(vl, alphaT, alphaB);
    float lambdaL = OpenPBR_Lambda_GGX_Aniso(ll, alphaT, alphaB);
    return 1.0 / max(1.0 + lambdaV + lambdaL, OPENPBR_EPSILON);
}

float3 OpenPBR_MicrofacetBRDF(float3 n, float3 t, float3 b, float3 v, float3 l, float2 alpha, float3 fresnel)
{
    float noL = saturate(dot(n, l));
    float noV = saturate(dot(n, v));

    if (noL <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float3 h = OpenPBR_SafeNormalize(l + v);
    float noH = saturate(dot(n, h));

    if (noH <= OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float d = OpenPBR_D_GGX_Aniso(h, n, t, b, alpha.x, alpha.y);
    float g = OpenPBR_G2_Smith_GGX_Aniso(v, l, n, t, b, alpha.x, alpha.y);
    return fresnel * d * g / max(4.0 * noL * noV, OPENPBR_EPSILON);
}

float3 OpenPBR_ThinFilmTintApprox(float cosTheta, float thicknessMicrometers, float filmIOR, float weight)
{
#if OPENPBR_USE_THIN_FILM_APPROX
    float w = saturate(weight);
    float thicknessNm = max(thicknessMicrometers, 0.0) * 1000.0;
    float eta = max(filmIOR, OPENPBR_EPSILON);
    float mu = saturate(cosTheta);
    float sinThetaFilmSq = (1.0 - mu * mu) / max(eta * eta, OPENPBR_EPSILON);
    float cosThetaFilm = sqrt(saturate(1.0 - sinThetaFilmSq));
    float3 wavelengthsNm = float3(650.0, 550.0, 450.0);
    float3 phase = 4.0 * OPENPBR_PI * eta * thicknessNm * cosThetaFilm / wavelengthsNm;
    float3 interference = 0.5 + 0.5 * cos(phase);
    float3 tint = saturate(0.35 + 0.65 * interference);
    return lerp(float3(1.0, 1.0, 1.0), tint, w);
#else
    return float3(1.0, 1.0, 1.0);
#endif
}

float3 OpenPBR_DielectricSpecularBRDF(OpenPBRMaterial m, float3 n, float3 t, float3 b, float3 v, float3 l, float roughness)
{
    float3 h = OpenPBR_SafeNormalize(l + v);
    float voH = saturate(dot(v, h));
    float etaRatio = OpenPBR_CoatedSpecularIORRatio(m.specular_ior, m.coat_ior, m.coat_weight, 1.0);
    float modulatedEta = OpenPBR_ModulatedIOR(etaRatio, m.specular_weight);
    float2 alpha = OpenPBR_AnisotropicRoughness(roughness, m.specular_roughness_anisotropy);
    float3 thinFilm = OpenPBR_ThinFilmTintApprox(voH, m.thin_film_thickness, m.thin_film_ior, m.thin_film_weight);
    float3 f = saturate(OpenPBR_FresnelDielectric(voH, modulatedEta) * m.specular_color * thinFilm);
    return OpenPBR_MicrofacetBRDF(n, t, b, v, l, alpha, f);
}

float3 OpenPBR_MetalBRDF(OpenPBRMaterial m, float3 n, float3 t, float3 b, float3 v, float3 l, float roughness)
{
    float3 h = OpenPBR_SafeNormalize(l + v);
    float voH = saturate(dot(v, h));
    float2 alpha = OpenPBR_AnisotropicRoughness(roughness, m.specular_roughness_anisotropy);
    float3 f0 = saturate(m.base_weight * m.base_color);
    float3 thinFilm = OpenPBR_ThinFilmTintApprox(voH, m.thin_film_thickness, m.thin_film_ior, m.thin_film_weight);
    float3 f = saturate(OpenPBR_FresnelMetalF82(voH, f0, m.specular_color, m.specular_weight) * thinFilm);
    return OpenPBR_MicrofacetBRDF(n, t, b, v, l, alpha, f);
}

float3 OpenPBR_OrenNayarDiffuseBRDF(float3 color, float weight, float roughness, float3 n, float3 v, float3 l)
{
    float noL = saturate(dot(n, l));
    float noV = saturate(dot(n, v));

    if (noL <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float sigma = saturate(roughness);
    float a = 1.0 / (1.0 + (0.5 - 2.0 / (3.0 * OPENPBR_PI)) * sigma);
    float b = sigma * a;
    float s = dot(l, v) - noL * noV;
    float invT = s <= 0.0 ? 1.0 : 1.0 / max(max(noL, noV), OPENPBR_EPSILON);
    float orenNayar = max(0.0, a + b * s * invT);

    return saturate(weight) * saturate(color) * OPENPBR_INV_PI * orenNayar;
}

float OpenPBR_HenyeyGreensteinPhase(float cosTheta, float anisotropy)
{
    float g = clamp(anisotropy, -0.999, 0.999);
    float g2 = g * g;
    float denom = pow(max(1.0 + g2 - 2.0 * g * cosTheta, OPENPBR_EPSILON), 1.5);
    return (1.0 - g2) / max(4.0 * OPENPBR_PI * denom, OPENPBR_EPSILON);
}

float3 OpenPBR_EvaluateVolumeTransmittance(OpenPBRVolumeProperties volume, float distance)
{
    float3 extinction = max(volume.extinction, float3(0.0, 0.0, 0.0));
    return exp(-extinction * max(distance, 0.0));
}

float OpenPBR_EvaluateVolumeDistancePdf(OpenPBRVolumeProperties volume, float distance, bool scattered)
{
    float3 extinction = max(volume.extinction, float3(0.0, 0.0, 0.0));
    float3 tr = exp(-extinction * max(distance, 0.0));

    if (scattered)
    {
        return max(dot(extinction * tr, float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)), 0.0);
    }

    return max(dot(tr, float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)), 0.0);
}

OpenPBRVolumeDistanceSample OpenPBR_SampleVolumeDistance(OpenPBRVolumeProperties volume, float distanceMax, float2 u)
{
    float3 absorption = max(volume.absorption, float3(0.0, 0.0, 0.0));
    float3 scattering = max(volume.scattering, float3(0.0, 0.0, 0.0));
    float3 extinction = max(volume.extinction, absorption + scattering);
    uint volumeFlags = volume.flags;
    volumeFlags |= (OpenPBR_Luminance(absorption) > 0.0) ? OPENPBR_VOLUME_ABSORBING : 0u;
    volumeFlags |= (OpenPBR_Luminance(scattering) > 0.0) ? OPENPBR_VOLUME_SCATTERING : 0u;

    OpenPBRVolumeProperties p = volume;
    p.absorption = absorption;
    p.scattering = scattering;
    p.extinction = extinction;
    p.flags = volumeFlags;

    OpenPBRVolumeDistanceSample sampleResult;
    sampleResult.distance = max(distanceMax, 0.0);
    sampleResult.transmittance = OpenPBR_EvaluateVolumeTransmittance(p, sampleResult.distance);
    sampleResult.pdf = 1.0;
    sampleResult.scattered = false;
    sampleResult.absorbed = false;
    sampleResult.event_flags = OPENPBR_EVENT_NONE;

    if ((p.flags & (OPENPBR_VOLUME_ABSORBING | OPENPBR_VOLUME_SCATTERING)) == 0u || distanceMax <= OPENPBR_EPSILON)
    {
        sampleResult.transmittance = float3(1.0, 1.0, 1.0);
        return sampleResult;
    }

    uint channel = min(2u, (uint)(saturate(u.x) * 3.0));
    float sigmaT = channel == 0u ? p.extinction.x : (channel == 1u ? p.extinction.y : p.extinction.z);

    if (sigmaT > OPENPBR_EPSILON)
    {
        float xi = min(saturate(u.y), 1.0 - OPENPBR_EPSILON);
        float sampledDistance = -log(max(1.0 - xi, OPENPBR_EPSILON)) / sigmaT;

        if (sampledDistance < distanceMax)
        {
            sampleResult.distance = sampledDistance;
            sampleResult.scattered = (OpenPBR_Luminance(p.scattering) > 0.0);
            sampleResult.absorbed = !sampleResult.scattered;
            sampleResult.event_flags = sampleResult.scattered ? OPENPBR_EVENT_VOLUME : OPENPBR_EVENT_NONE;
        }
    }

    sampleResult.transmittance = OpenPBR_EvaluateVolumeTransmittance(p, sampleResult.distance);
    sampleResult.pdf = OpenPBR_EvaluateVolumeDistancePdf(p, sampleResult.distance, sampleResult.scattered);
    return sampleResult;
}

float OpenPBR_EvaluateVolumePhase(OpenPBRVolumeProperties volume, float3 wo, float3 wi)
{
    float3 v = OpenPBR_SafeNormalize(wo);
    float3 l = OpenPBR_SafeNormalize(wi);
    return OpenPBR_HenyeyGreensteinPhase(dot(v, l), volume.anisotropy);
}

float OpenPBR_PdfVolumePhase(OpenPBRVolumeProperties volume, float3 wo, float3 wi)
{
    return OpenPBR_EvaluateVolumePhase(volume, wo, wi);
}

OpenPBRPhaseSample OpenPBR_SampleVolumePhase(OpenPBRVolumeProperties volume, float3 wo, float2 u)
{
    float3 v = OpenPBR_SafeNormalize(wo);
    float g = clamp(volume.anisotropy, -0.999, 0.999);
    float cosTheta;

    if (abs(g) < OPENPBR_EPSILON)
    {
        cosTheta = 1.0 - 2.0 * u.x;
    }
    else
    {
        float sqrTerm = (1.0 - g * g) / max(1.0 - g + 2.0 * g * u.x, OPENPBR_EPSILON);
        cosTheta = (1.0 + g * g - sqrTerm * sqrTerm) / max(2.0 * g, OPENPBR_EPSILON);
        cosTheta = clamp(cosTheta, -1.0, 1.0);
    }

    float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));
    float phi = 2.0 * OPENPBR_PI * u.y;
    float3 localDir = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    float3 tangent;
    float3 bitangent;
    OpenPBR_BuildOrthonormalFrame(v, abs(v.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0), tangent, bitangent);

    OpenPBRPhaseSample sampleResult;
    sampleResult.wi = OpenPBR_SafeNormalize(localDir.x * tangent + localDir.y * bitangent + localDir.z * v);
    sampleResult.phase = OpenPBR_EvaluateVolumePhase(volume, wo, sampleResult.wi);
    sampleResult.sample_pdf = sampleResult.phase;
    sampleResult.event_flags = OPENPBR_EVENT_VOLUME;
    return sampleResult;
}

OpenPBRVolumeProperties OpenPBR_EmptyVolumeProperties(float ior)
{
    OpenPBRVolumeProperties p = (OpenPBRVolumeProperties)0;
    p.ior = max(ior, OPENPBR_EPSILON);
    p.flags = OPENPBR_VOLUME_NONE;
    return p;
}

OpenPBRVolumeProperties OpenPBR_FinalizeVolumeProperties(OpenPBRVolumeProperties p)
{
    p.absorption = max(p.absorption, float3(0.0, 0.0, 0.0));
    p.scattering = max(p.scattering, float3(0.0, 0.0, 0.0));
    p.extinction = p.absorption + p.scattering;
    p.single_scatter_albedo = p.scattering / max(p.extinction, float3(OPENPBR_EPSILON, OPENPBR_EPSILON, OPENPBR_EPSILON));
    p.anisotropy = clamp(p.anisotropy, -0.999, 0.999);
    p.ior = max(p.ior, OPENPBR_EPSILON);
    p.flags &= ~(OPENPBR_VOLUME_ABSORBING | OPENPBR_VOLUME_SCATTERING);

    if (OpenPBR_Luminance(p.absorption) > 0.0)
    {
        p.flags |= OPENPBR_VOLUME_ABSORBING;
    }

    if (OpenPBR_Luminance(p.scattering) > 0.0)
    {
        p.flags |= OPENPBR_VOLUME_SCATTERING;
    }

    return p;
}

OpenPBRVolumeProperties OpenPBR_GetSubsurfaceVolumeProperties(OpenPBRMaterial material)
{
    OpenPBRVolumeProperties p = OpenPBR_EmptyVolumeProperties(material.specular_ior);
    float3 radius = max(material.subsurface_radius * material.subsurface_radius_scale, float3(OPENPBR_EPSILON, OPENPBR_EPSILON, OPENPBR_EPSILON));
    float3 color = saturate(material.subsurface_color);
    float g = clamp(material.subsurface_scatter_anisotropy, -0.999, 0.999);
    float3 colorSq = color * color;
    float3 s = 4.09712 + 4.20863 * color - sqrt(max(9.59217 + 41.6808 * color + 17.7126 * colorSq, float3(0.0, 0.0, 0.0)));
    float3 s2 = s * s;
    float3 alpha = saturate((1.0 - s2) / max(1.0 - g * s2, float3(OPENPBR_EPSILON, OPENPBR_EPSILON, OPENPBR_EPSILON)));

    p.extinction = 1.0 / radius;
    p.scattering = p.extinction * alpha;
    p.absorption = max(p.extinction - p.scattering, float3(0.0, 0.0, 0.0));
    p.single_scatter_albedo = alpha;
    p.anisotropy = g;
    p.ior = max(material.specular_ior, OPENPBR_EPSILON);
    p.flags = OPENPBR_VOLUME_SUBSURFACE;
    return OpenPBR_FinalizeVolumeProperties(p);
}

OpenPBRVolumeProperties OpenPBR_GetTransmissionVolumeProperties(OpenPBRMaterial material)
{
    OpenPBRVolumeProperties p = OpenPBR_EmptyVolumeProperties(material.specular_ior);
    p.anisotropy = clamp(material.transmission_scatter_anisotropy, -0.999, 0.999);
    p.flags = OPENPBR_VOLUME_TRANSMISSION;

    if (material.transmission_depth <= OPENPBR_EPSILON)
    {
        return OpenPBR_FinalizeVolumeProperties(p);
    }

    float depth = max(material.transmission_depth, OPENPBR_EPSILON);
    float3 transmissionColor = OpenPBR_SafePositive(saturate(material.transmission_color));
    p.extinction = -log(transmissionColor) / depth;
    p.scattering = saturate(material.transmission_scatter) / depth;
    p.absorption = p.extinction - p.scattering;

    float minAbsorption = min(p.absorption.x, min(p.absorption.y, p.absorption.z));
    if (minAbsorption < 0.0)
    {
        p.absorption -= minAbsorption;
    }

    p.ior = max(material.specular_ior, OPENPBR_EPSILON);
    return OpenPBR_FinalizeVolumeProperties(p);
}

OpenPBRVolumeProperties OpenPBR_GetCoatVolumeProperties(OpenPBRMaterial material)
{
    OpenPBRVolumeProperties p = OpenPBR_EmptyVolumeProperties(material.coat_ior);
    float3 singlePassTint = sqrt(OpenPBR_SafePositive(saturate(material.coat_color)));
    p.absorption = -log(singlePassTint);
    p.ior = max(material.coat_ior, OPENPBR_EPSILON);
    p.flags = OPENPBR_VOLUME_COAT;
    return OpenPBR_FinalizeVolumeProperties(p);
}

OpenPBRVolumeProperties OpenPBR_GetMaterialVolumeProperties(OpenPBRMaterial material, uint selectorFlags)
{
    selectorFlags = OpenPBR_NormalizeVolumeSelector(selectorFlags);

    if ((selectorFlags & OPENPBR_VOLUME_COAT) != 0u)
    {
        return OpenPBR_GetCoatVolumeProperties(material);
    }

    if ((selectorFlags & OPENPBR_VOLUME_SUBSURFACE) != 0u)
    {
        return OpenPBR_GetSubsurfaceVolumeProperties(material);
    }

    if ((selectorFlags & OPENPBR_VOLUME_TRANSMISSION) != 0u)
    {
        return OpenPBR_GetTransmissionVolumeProperties(material);
    }

    return OpenPBR_EmptyVolumeProperties(1.0);
}

OpenPBRVolumeProperties OpenPBR_GetPackedMaterialVolumeProperties(PackedOpenPBRMaterial packedMaterial, uint selectorFlags)
{
    return OpenPBR_GetMaterialVolumeProperties(UnpackOpenPBRMaterial(packedMaterial), selectorFlags);
}

OpenPBRVolumeProperties OpenPBR_GetPayloadVolumeProperties(OpenPBRPayload payload, uint selectorFlags)
{
    return OpenPBR_GetPackedMaterialVolumeProperties(payload.material, selectorFlags);
}

OpenPBRVolumeProperties OpenPBR_GetPayloadVolumeProperties(OpenPBRPayload payload)
{
    uint selectorFlags = OpenPBR_GetSurfaceVolumeSelector(payload.surfaceCtx);
    return OpenPBR_GetPayloadVolumeProperties(payload, selectorFlags);
}

float OpenPBR_DispersedIOR(float baseIOR, float dispersionScale, float abbeNumber, float wavelengthNm)
{
    float scale = saturate(dispersionScale);
    if (scale <= OPENPBR_EPSILON)
    {
        return baseIOR;
    }

    float vd = max(abbeNumber / max(scale, OPENPBR_EPSILON), OPENPBR_EPSILON);
    float lambdaC = 656.3;
    float lambdaD = 587.6;
    float lambdaF = 486.1;
    float invF2 = 1.0 / (lambdaF * lambdaF);
    float invC2 = 1.0 / (lambdaC * lambdaC);
    float b = (baseIOR - 1.0) / max(vd * (invF2 - invC2), OPENPBR_EPSILON);
    float a = baseIOR - b / (lambdaD * lambdaD);
    return a + b / max(wavelengthNm * wavelengthNm, OPENPBR_EPSILON);
}

float3 OpenPBR_BeerTransmittanceFromColor(float3 transmissionColor, float transmissionDepth, float distance)
{
    if (transmissionDepth <= OPENPBR_EPSILON)
    {
        return saturate(transmissionColor);
    }

    float3 extinction = -log(OpenPBR_SafePositive(saturate(transmissionColor))) / max(transmissionDepth, OPENPBR_EPSILON);
    return exp(-extinction * max(distance, 0.0));
}

float3 OpenPBR_FuzzBRDFApprox(float3 fuzzColor, float fuzzRoughness, float3 n, float3 v, float3 l)
{
    float noL = saturate(dot(n, l));
    float noV = saturate(dot(n, v));

    if (noL <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float3 h = OpenPBR_SafeNormalize(l + v);
    float noH = saturate(dot(n, h));
    float sinThetaH = sqrt(saturate(1.0 - noH * noH));
    float roughness = max(saturate(fuzzRoughness), 0.001);
    float invR = 1.0 / roughness;
    float dCharlie = (2.0 + invR) * pow(sinThetaH, invR) / (2.0 * OPENPBR_PI);
    float visibility = 1.0 / max(4.0 * (noL + noV - noL * noV), OPENPBR_EPSILON);
    return saturate(fuzzColor) * dCharlie * visibility;
}

float OpenPBR_FuzzAlbedoEstimate(float noV, float fuzzRoughness)
{
    float grazing = 1.0 - saturate(noV);
    float rough = saturate(fuzzRoughness);
    return saturate(0.12 + 0.68 * pow(grazing, lerp(0.75, 2.5, rough)));
}

float3 OpenPBR_CoatAbsorption(OpenPBRMaterial m, float noL, float noV)
{
    float eta = max(m.coat_ior, OPENPBR_EPSILON);
    float eta2 = eta * eta;
    float muL = sqrt(saturate(1.0 - (1.0 - noL * noL) / eta2));
    float muV = sqrt(saturate(1.0 - (1.0 - noV * noV) / eta2));
    float exponent = 1.0 / max(muL, OPENPBR_EPSILON) + 1.0 / max(muV, OPENPBR_EPSILON);
    float3 singlePassTint = sqrt(OpenPBR_SafePositive(m.coat_color));
    return saturate(pow(singlePassTint, exponent));
}

float3 OpenPBR_CoatEmissionAbsorption(OpenPBRMaterial m, float noV)
{
    float eta = max(m.coat_ior, OPENPBR_EPSILON);
    float muV = sqrt(saturate(1.0 - (1.0 - noV * noV) / max(eta * eta, OPENPBR_EPSILON)));
    float3 singlePassTint = sqrt(OpenPBR_SafePositive(m.coat_color));
    return saturate(pow(singlePassTint, 1.0 / max(muV, OPENPBR_EPSILON)));
}

float3 OpenPBR_BaseAlbedoEstimate(OpenPBRMaterial m)
{
    float3 eMetal = saturate(m.base_color * m.specular_weight);
    float3 eDielectricOpaque = lerp(saturate(m.base_color), saturate(m.subsurface_color), m.subsurface_weight);
    float3 eDielectric = lerp(eDielectricOpaque, saturate(m.transmission_color), m.transmission_weight);
    return lerp(eDielectric, eMetal, m.base_metalness);
}

float3 OpenPBR_CoatDarkeningFactor(OpenPBRMaterial m, float noV)
{
    float eta = max(m.coat_ior, OPENPBR_EPSILON);
    float eF = OpenPBR_AverageFresnelDielectric(eta);
    float kRough = 1.0 - (1.0 - eF) / max(eta * eta, OPENPBR_EPSILON);
    float kSmooth = OpenPBR_FresnelDielectric(noV, eta);

    float baseEta = max(m.specular_ior, OPENPBR_EPSILON);
    float specF0 = OpenPBR_IORToF0(baseEta);
    float dielectricRoughness = lerp(1.0, m.specular_roughness, saturate(m.specular_weight * specF0));
    float metalRoughness = m.specular_roughness;
    float baseRoughness = lerp(dielectricRoughness, metalRoughness, m.base_metalness);
    float k = lerp(kSmooth, kRough, saturate(baseRoughness));

    float3 eb = OpenPBR_BaseAlbedoEstimate(m);
    float3 delta = (1.0 - k) / max(1.0 - eb * k, float3(OPENPBR_EPSILON, OPENPBR_EPSILON, OPENPBR_EPSILON));
    return lerp(float3(1.0, 1.0, 1.0), saturate(delta), saturate(m.coat_weight * m.coat_darkening));
}

float3 OpenPBR_CoatBRDF(OpenPBRMaterial m, float3 n, float3 t, float3 b, float3 v, float3 l)
{
    float3 h = OpenPBR_SafeNormalize(l + v);
    float voH = saturate(dot(v, h));
    float2 alpha = OpenPBR_AnisotropicRoughness(m.coat_roughness, m.coat_roughness_anisotropy);
    float fresnel = OpenPBR_FresnelDielectric(voH, m.coat_ior);
    return OpenPBR_MicrofacetBRDF(n, t, b, v, l, alpha, float3(fresnel, fresnel, fresnel));
}

float3 OpenPBR_ToWorld(float3 value, float3 normalWS, float3 tangentWS, float3 bitangentWS)
{
    return value.x * tangentWS + value.y * bitangentWS + value.z * normalWS;
}

float3 OpenPBR_SampleCosineHemisphere(float2 u)
{
    float r = sqrt(saturate(u.x));
    float phi = 2.0 * OPENPBR_PI * u.y;
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(saturate(1.0 - u.x));
    return float3(x, y, z);
}

float OpenPBR_G1_Smith_GGX_Aniso(float3 w, float3 n, float3 t, float3 b, float alphaT, float alphaB)
{
    float3 wl = OpenPBR_ToLocal(w, n, t, b);
    return 1.0 / max(1.0 + OpenPBR_Lambda_GGX_Aniso(wl, alphaT, alphaB), OPENPBR_EPSILON);
}

float3 OpenPBR_SampleGGXVNDF_Aniso(float3 n, float3 t, float3 b, float3 v, float2 alpha, float2 u)
{
    float3 vl = OpenPBR_ToLocal(v, n, t, b);
    float alphaT = max(alpha.x, 0.001);
    float alphaB = max(alpha.y, 0.001);
    vl = OpenPBR_SafeNormalize(float3(alphaT * vl.x, alphaB * vl.y, max(vl.z, OPENPBR_EPSILON)));

    float lensq = vl.x * vl.x + vl.y * vl.y;
    float3 t1 = lensq > OPENPBR_EPSILON ? float3(-vl.y, vl.x, 0.0) * rsqrt(lensq) : float3(1.0, 0.0, 0.0);
    float3 t2 = cross(vl, t1);

    float r = sqrt(saturate(u.x));
    float phi = 2.0 * OPENPBR_PI * u.y;
    float p1 = r * cos(phi);
    float p2 = r * sin(phi);
    float s = 0.5 * (1.0 + vl.z);
    p2 = lerp(sqrt(saturate(1.0 - p1 * p1)), p2, s);

    float3 nh = p1 * t1 + p2 * t2 + sqrt(saturate(1.0 - p1 * p1 - p2 * p2)) * vl;
    float3 hLocal = OpenPBR_SafeNormalize(float3(alphaT * nh.x, alphaB * nh.y, max(nh.z, 0.0)));
    return OpenPBR_SafeNormalize(OpenPBR_ToWorld(hLocal, n, t, b));
}

float OpenPBR_GGXVNDFHalfVectorPdf(float3 n, float3 t, float3 b, float3 v, float3 h, float2 alpha)
{
    float noV = saturate(dot(n, v));
    float voH = abs(dot(v, h));
    float noH = dot(n, h);

    if (noV <= OPENPBR_EPSILON || voH <= OPENPBR_EPSILON || noH <= OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float alphaT = max(alpha.x, 0.001);
    float alphaB = max(alpha.y, 0.001);
    float d = OpenPBR_D_GGX_Aniso(h, n, t, b, alphaT, alphaB);
    float g1 = OpenPBR_G1_Smith_GGX_Aniso(v, n, t, b, alphaT, alphaB);
    return d * g1 * voH / max(noV, OPENPBR_EPSILON);
}

float OpenPBR_GGXVNDFReflectionPdf(float3 n, float3 t, float3 b, float3 v, float3 l, float2 alpha)
{
    float noL = saturate(dot(n, l));
    float noV = saturate(dot(n, v));

    if (noL <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float3 h = OpenPBR_SafeNormalize(l + v);
    float voH = abs(dot(v, h));
    if (voH <= OPENPBR_EPSILON)
    {
        return 0.0;
    }

    return OpenPBR_GGXVNDFHalfVectorPdf(n, t, b, v, h, alpha) / max(4.0 * voH, OPENPBR_EPSILON);
}

float3 OpenPBR_ThinWalledTransmissionBTDF(OpenPBRMaterial m, float3 n, float3 v, float3 l)
{
    float noV = dot(n, v);
    float noL = dot(n, l);

    if (noV <= OPENPBR_EPSILON || noL >= -OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float g = clamp(m.subsurface_scatter_anisotropy, -1.0, 1.0);
    float transmitW = 0.5 * (1.0 + g);
    float3 baseTransmit = saturate(m.transmission_weight) * saturate(m.transmission_color);
    float3 sssTransmit = saturate(m.subsurface_weight) * transmitW * saturate(m.subsurface_color);
    float3 transmittance = (baseTransmit + sssTransmit) * (1.0 - saturate(m.base_metalness));
    return saturate(m.base_weight) * transmittance * OPENPBR_INV_PI;
}

float3 OpenPBR_DielectricTransmissionBTDF(OpenPBRMaterial m, float3 n, float3 t, float3 b, float3 v, float3 l, float roughness, float etaI, float etaT)
{
    float noV = dot(n, v);
    float noL = dot(n, l);

    if (noV <= OPENPBR_EPSILON || noL >= -OPENPBR_EPSILON || m.transmission_weight <= OPENPBR_EPSILON || m.base_metalness >= 1.0)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float3 h = OpenPBR_SafeNormalize(etaI * v + etaT * l);
    if (dot(h, n) < 0.0)
    {
        h = -h;
    }

    float voH = abs(dot(v, h));
    float loH = abs(dot(l, h));
    float noH = saturate(dot(n, h));

    if (voH <= OPENPBR_EPSILON || loH <= OPENPBR_EPSILON || noH <= OPENPBR_EPSILON)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float2 alpha = OpenPBR_AnisotropicRoughness(roughness, m.specular_roughness_anisotropy);
    float d = OpenPBR_D_GGX_Aniso(h, n, t, b, alpha.x, alpha.y);
    float g = OpenPBR_G2_Smith_GGX_Aniso(v, l, n, t, b, alpha.x, alpha.y);
    float f = OpenPBR_FresnelDielectric(voH, etaT / max(etaI, OPENPBR_EPSILON));
    float denom = etaI * voH + etaT * loH;
    float jacobian = (etaT * etaT * voH * loH) / max(abs(noV * noL) * denom * denom, OPENPBR_EPSILON);
    float3 thinFilm = OpenPBR_ThinFilmTintApprox(voH, m.thin_film_thickness, m.thin_film_ior, m.thin_film_weight);
    float3 transmittance = saturate(m.transmission_color) * saturate(m.base_weight) * (1.0 - saturate(m.base_metalness));
    return saturate(m.transmission_weight) * transmittance * thinFilm * (1.0 - f) * d * g * jacobian;
}

float OpenPBR_GGXVNDFTransmissionPdf(float3 n, float3 t, float3 b, float3 v, float3 l, float2 alpha, float etaI, float etaT)
{
    float noV = dot(n, v);
    float noL = dot(n, l);

    if (noV <= OPENPBR_EPSILON || noL >= -OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float3 h = OpenPBR_SafeNormalize(etaI * v + etaT * l);
    if (dot(h, n) < 0.0)
    {
        h = -h;
    }

    float noH = saturate(dot(n, h));
    float loH = abs(dot(l, h));
    float voH = abs(dot(v, h));

    if (noH <= OPENPBR_EPSILON || loH <= OPENPBR_EPSILON || voH <= OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float denom = etaI * voH + etaT * loH;
    float dwhDwi = (etaT * etaT * loH) / max(denom * denom, OPENPBR_EPSILON);
    return OpenPBR_GGXVNDFHalfVectorPdf(n, t, b, v, h, alpha) * dwhDwi;
}

void OpenPBR_GetSurfaceSamplingWeights(OpenPBRMaterial m, bool thinWalled, out float diffuseWeight, out float baseSpecularWeight, out float coatWeight, out float transmissionWeight)
{
    float dielectricWeight = 1.0 - saturate(m.base_metalness);
    float opaqueWeight = 1.0 - saturate(m.transmission_weight);
    float diffuseAlbedo = OpenPBR_Luminance(lerp(saturate(m.base_color), saturate(m.subsurface_color), saturate(m.subsurface_weight)));
    float metalAlbedo = OpenPBR_Luminance(saturate(m.base_color));
    float fuzzAlbedo = OpenPBR_Luminance(saturate(m.fuzz_color));
    float transmissionAlbedo = OpenPBR_Luminance(saturate(m.transmission_color));
    float thinTransmissionAlbedo = OpenPBR_Luminance(saturate(m.subsurface_color));

    diffuseWeight = saturate(m.base_weight) * dielectricWeight * opaqueWeight * diffuseAlbedo;
    diffuseWeight += saturate(m.fuzz_weight) * fuzzAlbedo;
    baseSpecularWeight = max(0.0, m.specular_weight) * dielectricWeight + metalAlbedo * saturate(m.base_metalness);
    coatWeight = saturate(m.coat_weight);
    transmissionWeight = dielectricWeight * saturate(m.transmission_weight) * max(transmissionAlbedo, OPENPBR_EPSILON);
    transmissionWeight += thinWalled ? dielectricWeight * saturate(m.subsurface_weight) * thinTransmissionAlbedo : 0.0;

    float sum = diffuseWeight + baseSpecularWeight + coatWeight + transmissionWeight;
    if (sum <= OPENPBR_EPSILON)
    {
        diffuseWeight = 1.0;
        baseSpecularWeight = 0.0;
        coatWeight = 0.0;
        transmissionWeight = 0.0;
    }
}

float OpenPBR_PdfSurface(OpenPBRMaterial material, OpenPBRSurfaceCtx ctx, float3 wo, float3 wi)
{
    OpenPBRMaterial m = OpenPBR_SanitizeMaterial(material);
    float3 n = OpenPBR_SafeNormalize(ctx.shading_normal);
    float3 coatN = OpenPBR_SafeNormalize(ctx.shading_coat_normal);
    float3 v = OpenPBR_SafeNormalize(wo);
    float3 l = OpenPBR_SafeNormalize(wi);

    if (dot(n, v) < 0.0)
    {
        n = -n;
    }

    if (dot(coatN, v) < 0.0)
    {
        coatN = -coatN;
    }

    float3 t;
    float3 b;
    float3 coatT;
    float3 coatB;
    OpenPBR_BuildOrthonormalFrame(n, ctx.shading_tangent, t, b);
    OpenPBR_BuildOrthonormalFrame(coatN, ctx.shading_coat_tangent, coatT, coatB);

    float noL = dot(n, l);
    float noV = dot(n, v);
    if (abs(noL) <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        return 0.0;
    }

    float diffuseWeight;
    float baseSpecularWeight;
    float coatWeight;
    float transmissionWeight;
    OpenPBR_GetSurfaceSamplingWeights(m, ctx.geometry_thin_walled, diffuseWeight, baseSpecularWeight, coatWeight, transmissionWeight);

    float weightSum = diffuseWeight + baseSpecularWeight + coatWeight + transmissionWeight;
    float invWeightSum = 1.0 / max(weightSum, OPENPBR_EPSILON);
    diffuseWeight *= invWeightSum;
    baseSpecularWeight *= invWeightSum;
    coatWeight *= invWeightSum;
    transmissionWeight *= invWeightSum;

    float effectiveBaseRoughness = OpenPBR_CoatAffectedBaseRoughness(m.specular_roughness, m.coat_roughness, m.coat_weight);
    float2 baseAlpha = OpenPBR_AnisotropicRoughness(effectiveBaseRoughness, m.specular_roughness_anisotropy);
    float2 coatAlpha = OpenPBR_AnisotropicRoughness(m.coat_roughness, m.coat_roughness_anisotropy);

    if (noL > OPENPBR_EPSILON)
    {
        float diffusePdf = noL * OPENPBR_INV_PI;
        float baseSpecularPdf = OpenPBR_GGXVNDFReflectionPdf(n, t, b, v, l, baseAlpha);
        float coatSpecularPdf = OpenPBR_GGXVNDFReflectionPdf(coatN, coatT, coatB, v, l, coatAlpha);
        return diffuseWeight * diffusePdf + baseSpecularWeight * baseSpecularPdf + coatWeight * coatSpecularPdf;
    }

    if (ctx.geometry_thin_walled)
    {
        return transmissionWeight * (-noL) * OPENPBR_INV_PI;
    }

    float etaRatio = OpenPBR_CoatedSpecularIORRatio(m.specular_ior, m.coat_ior, m.coat_weight, 1.0);
    float modulatedEta = OpenPBR_ModulatedIOR(etaRatio, m.specular_weight);
    float etaI = ctx.geometry_front_face ? 1.0 : modulatedEta;
    float etaT = ctx.geometry_front_face ? modulatedEta : 1.0;
    float transmissionPdf = OpenPBR_GGXVNDFTransmissionPdf(n, t, b, v, l, baseAlpha, etaI, etaT);
    return transmissionWeight * transmissionPdf;
}

float3 OpenPBR_EvaluateSurfaceEmission(OpenPBRMaterial m, OpenPBRSurfaceCtx ctx, float coatNoV)
{
    if (!ctx.geometry_front_face && !ctx.geometry_thin_walled)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float3 emissionBase = m.emission_luminance * m.emission_color;
    float3 emissionCoatScale = lerp(float3(1.0, 1.0, 1.0), OpenPBR_CoatEmissionAbsorption(m, coatNoV), m.coat_weight);
    return ctx.geometry_opacity * emissionBase * emissionCoatScale;
}

OpenPBRPathResult OpenPBR_EvaluateSurface(OpenPBRMaterial material, OpenPBRSurfaceCtx ctx, float3 wo, float3 wi)
{
    OpenPBRMaterial m = OpenPBR_SanitizeMaterial(material);
    
    float3 n = OpenPBR_SafeNormalize(ctx.shading_normal);
    float3 coatN = OpenPBR_SafeNormalize(ctx.shading_coat_normal);
    float3 v = OpenPBR_SafeNormalize(wo);
    float3 l = OpenPBR_SafeNormalize(wi);

    if (dot(n, v) < 0.0)
    {
        n = -n;
    }

    if (dot(coatN, v) < 0.0)
    {
        coatN = -coatN;
    }

    float3 t;
    float3 b;
    float3 coatT;
    float3 coatB;
    OpenPBR_BuildOrthonormalFrame(n, ctx.shading_tangent, t, b);
    OpenPBR_BuildOrthonormalFrame(coatN, ctx.shading_coat_tangent, coatT, coatB);
    
    float signedNoL = dot(n, l);
    float noL = saturate(signedNoL);
    float noV = saturate(dot(n, v));
    float absNoL = abs(signedNoL);
    float coatNoL = saturate(dot(coatN, l));
    float coatNoV = saturate(dot(coatN, v));

    OpenPBRPathResult result;
    result.bsdf = float3(0.0, 0.0, 0.0);
    result.weighted_bsdf = float3(0.0, 0.0, 0.0);
    result.emission = float3(0.0, 0.0, 0.0);
    result.continuation_weight = ctx.geometry_opacity * OpenPBR_BaseAlbedoEstimate(m);
    result.sample_pdf = OpenPBR_PdfSurface(m, ctx, wo, wi);
    result.eta = 1.0;
    result.opacity = ctx.geometry_opacity;
    result.event_flags = OPENPBR_EVENT_NONE;
    
    if (ctx.geometry_opacity < 1.0)
    {
        result.event_flags |= OPENPBR_EVENT_NULL;
    }

    if (absNoL <= OPENPBR_EPSILON || noV <= OPENPBR_EPSILON)
    {
        result.emission = OpenPBR_EvaluateSurfaceEmission(m, ctx, coatNoV);

        if (OpenPBR_Luminance(result.emission) > 0.0)
        {
            result.event_flags |= OPENPBR_EVENT_EMISSION;
        }

        return result;
    }

    float effectiveBaseRoughness = OpenPBR_CoatAffectedBaseRoughness(m.specular_roughness, m.coat_roughness, m.coat_weight);
    float etaRatio = OpenPBR_CoatedSpecularIORRatio(m.specular_ior, m.coat_ior, m.coat_weight, 1.0);
    float modulatedEta = OpenPBR_ModulatedIOR(etaRatio, m.specular_weight);
    result.eta = ctx.geometry_thin_walled ? 1.0 : modulatedEta;

    if (signedNoL < -OPENPBR_EPSILON)
    {
        float3 transmissionBTDF;
        if (ctx.geometry_thin_walled)
        {
            transmissionBTDF = OpenPBR_ThinWalledTransmissionBTDF(m, n, v, l);
            result.event_flags |= OPENPBR_EVENT_DIFFUSE;
        }
        else
        {
            float etaI = ctx.geometry_front_face ? 1.0 : modulatedEta;
            float etaT = ctx.geometry_front_face ? modulatedEta : 1.0;
            result.eta = etaT / max(etaI, OPENPBR_EPSILON);
            transmissionBTDF = OpenPBR_DielectricTransmissionBTDF(m, n, t, b, v, l, effectiveBaseRoughness, etaI, etaT);
            result.event_flags |= OPENPBR_EVENT_GLOSSY;
        }

        result.emission = OpenPBR_EvaluateSurfaceEmission(m, ctx, coatNoV);
        result.bsdf = ctx.geometry_opacity * transmissionBTDF;
        result.weighted_bsdf = result.bsdf * absNoL;
        result.continuation_weight = saturate(ctx.geometry_opacity * saturate(m.transmission_color));
        result.event_flags |= OPENPBR_EVENT_TRANSMISSION;

        if (OpenPBR_Luminance(result.emission) > 0.0)
        {
            result.event_flags |= OPENPBR_EVENT_EMISSION;
        }

        return result;
    }

    float3 dielectricSpecular = OpenPBR_DielectricSpecularBRDF(m, n, t, b, v, l, effectiveBaseRoughness);
    float3 metal = OpenPBR_MetalBRDF(m, n, t, b, v, l, effectiveBaseRoughness);

    float3 diffuse = OpenPBR_OrenNayarDiffuseBRDF(m.base_color, m.base_weight, m.base_diffuse_roughness, n, v, l);
    float3 sssReflection = OpenPBR_OrenNayarDiffuseBRDF(m.subsurface_color, m.base_weight, m.base_diffuse_roughness, n, v, l);

    float thinReflectionWeight = 1.0;
    if (ctx.geometry_thin_walled)
    {
        float g = clamp(m.subsurface_scatter_anisotropy, -1.0, 1.0);
        float reflectW = 0.5 * (1.0 - g);
        sssReflection *= reflectW;
        thinReflectionWeight = 1.0 - m.transmission_weight;
    }

    float dielectricAlbedo = OpenPBR_FresnelDielectric(noV, modulatedEta);
    float3 specEnergyScale = saturate(1.0 - dielectricAlbedo * m.specular_color);

    float3 opaqueSubstrate = lerp(diffuse, sssReflection, m.subsurface_weight);
    float3 reflectiveDielectricSubstrate = thinReflectionWeight * lerp(opaqueSubstrate, float3(0.0, 0.0, 0.0), m.transmission_weight);
    float3 dielectricBase = dielectricSpecular + specEnergyScale * reflectiveDielectricSubstrate;
    float3 baseSubstrate = lerp(dielectricBase, metal, m.base_metalness);

    float3 coatAbsorption = OpenPBR_CoatAbsorption(m, coatNoL, coatNoV);
    float coatAlbedo = OpenPBR_FresnelDielectric(coatNoV, m.coat_ior);
    float3 coatDarkening = OpenPBR_CoatDarkeningFactor(m, coatNoV);
    float3 coatBaseScale = lerp(float3(1.0, 1.0, 1.0), coatAbsorption * (1.0 - coatAlbedo), m.coat_weight) * coatDarkening;
    float3 coatBRDF = m.coat_weight * OpenPBR_CoatBRDF(m, coatN, coatT, coatB, v, l);
    float3 coatedBase = coatBRDF + coatBaseScale * baseSubstrate;

    float3 fuzzN = OpenPBR_SafeNormalize(lerp(n, coatN, m.coat_weight));
    float3 fuzzBRDF = m.fuzz_weight * OpenPBR_FuzzBRDFApprox(m.fuzz_color, m.fuzz_roughness, fuzzN, v, l);
    float fuzzAlbedo = OpenPBR_FuzzAlbedoEstimate(saturate(dot(fuzzN, v)), m.fuzz_roughness);
    float fuzzBaseScale = lerp(1.0, 1.0 - fuzzAlbedo, m.fuzz_weight);

    float3 brdf = fuzzBRDF + fuzzBaseScale * coatedBase;

    result.emission = OpenPBR_EvaluateSurfaceEmission(m, ctx, coatNoV);
    result.bsdf = ctx.geometry_opacity * brdf;
    result.weighted_bsdf = result.bsdf * noL;

    float3 continuationBase = OpenPBR_BaseAlbedoEstimate(m);
    float3 continuationCoat = lerp(continuationBase, max(continuationBase, coatAbsorption), m.coat_weight);
    float3 continuationFuzz = lerp(continuationCoat, max(continuationCoat, m.fuzz_color * fuzzAlbedo), m.fuzz_weight);
    result.continuation_weight = saturate(ctx.geometry_opacity * continuationFuzz);
    
    result.event_flags |= OPENPBR_EVENT_REFLECTION;

    if (m.base_metalness < 1.0 && (m.transmission_weight < 1.0 || m.subsurface_weight > 0.0))
    {
        result.event_flags |= OPENPBR_EVENT_DIFFUSE;
    }

    if (m.specular_weight > 0.0 || m.base_metalness > 0.0 || m.coat_weight > 0.0 || m.fuzz_weight > 0.0)
    {
        result.event_flags |= OPENPBR_EVENT_GLOSSY;
    }

    if (m.base_metalness < 1.0 && (m.transmission_weight > 0.0 || (ctx.geometry_thin_walled && m.subsurface_weight > 0.0)))
    {
        result.event_flags |= OPENPBR_EVENT_TRANSMISSION;
    }

    if (!ctx.geometry_thin_walled && m.base_metalness < 1.0 && m.subsurface_weight > 0.0)
    {
        result.event_flags |= OPENPBR_EVENT_VOLUME;
    }

    if (OpenPBR_Luminance(result.emission) > 0.0)
    {
        result.event_flags |= OPENPBR_EVENT_EMISSION;
    }

    return result;
}

OpenPBRPathResult OpenPBR_SampleSurface(OpenPBRMaterial material, OpenPBRSurfaceCtx ctx, float3 wo, float3 u, out float3 wi)
{
    OpenPBRMaterial m = OpenPBR_SanitizeMaterial(material);
    float3 n = OpenPBR_SafeNormalize(ctx.shading_normal);
    float3 coatN = OpenPBR_SafeNormalize(ctx.shading_coat_normal);
    float3 v = OpenPBR_SafeNormalize(wo);

    if (dot(n, v) < 0.0)
    {
        n = -n;
    }

    if (dot(coatN, v) < 0.0)
    {
        coatN = -coatN;
    }

    float3 t;
    float3 b;
    float3 coatT;
    float3 coatB;
    OpenPBR_BuildOrthonormalFrame(n, ctx.shading_tangent, t, b);
    OpenPBR_BuildOrthonormalFrame(coatN, ctx.shading_coat_tangent, coatT, coatB);

    float diffuseWeight;
    float baseSpecularWeight;
    float coatWeight;
    float transmissionWeight;
    OpenPBR_GetSurfaceSamplingWeights(m, ctx.geometry_thin_walled, diffuseWeight, baseSpecularWeight, coatWeight, transmissionWeight);

    float weightSum = diffuseWeight + baseSpecularWeight + coatWeight + transmissionWeight;
    float invWeightSum = 1.0 / max(weightSum, OPENPBR_EPSILON);
    diffuseWeight *= invWeightSum;
    baseSpecularWeight *= invWeightSum;
    coatWeight *= invWeightSum;
    transmissionWeight *= invWeightSum;

    float selector = saturate(u.z);
    if (selector < diffuseWeight)
    {
        wi = OpenPBR_SafeNormalize(OpenPBR_ToWorld(OpenPBR_SampleCosineHemisphere(u.xy), n, t, b));
    }
    else if (selector < diffuseWeight + baseSpecularWeight)
    {
        float effectiveBaseRoughness = OpenPBR_CoatAffectedBaseRoughness(m.specular_roughness, m.coat_roughness, m.coat_weight);
        float2 alpha = OpenPBR_AnisotropicRoughness(effectiveBaseRoughness, m.specular_roughness_anisotropy);
        float3 h = OpenPBR_SampleGGXVNDF_Aniso(n, t, b, v, alpha, u.xy);
        wi = OpenPBR_SafeNormalize(reflect(-v, h));
    }
    else if (selector < diffuseWeight + baseSpecularWeight + coatWeight)
    {
        float2 alpha = OpenPBR_AnisotropicRoughness(m.coat_roughness, m.coat_roughness_anisotropy);
        float3 h = OpenPBR_SampleGGXVNDF_Aniso(coatN, coatT, coatB, v, alpha, u.xy);
        wi = OpenPBR_SafeNormalize(reflect(-v, h));
    }
    else if (ctx.geometry_thin_walled)
    {
        float3 transmissionT;
        float3 transmissionB;
        OpenPBR_BuildOrthonormalFrame(-n, ctx.shading_tangent, transmissionT, transmissionB);
        wi = OpenPBR_SafeNormalize(OpenPBR_ToWorld(OpenPBR_SampleCosineHemisphere(u.xy), -n, transmissionT, transmissionB));
    }
    else
    {
        float effectiveBaseRoughness = OpenPBR_CoatAffectedBaseRoughness(m.specular_roughness, m.coat_roughness, m.coat_weight);
        float2 alpha = OpenPBR_AnisotropicRoughness(effectiveBaseRoughness, m.specular_roughness_anisotropy);
        float3 h = OpenPBR_SampleGGXVNDF_Aniso(n, t, b, v, alpha, u.xy);
        if (dot(h, v) < 0.0)
        {
            h = -h;
        }

        float etaRatio = OpenPBR_CoatedSpecularIORRatio(m.specular_ior, m.coat_ior, m.coat_weight, 1.0);
        float modulatedEta = OpenPBR_ModulatedIOR(etaRatio, m.specular_weight);
        float etaI = ctx.geometry_front_face ? 1.0 : modulatedEta;
        float etaT = ctx.geometry_front_face ? modulatedEta : 1.0;
        wi = refract(-v, h, etaI / max(etaT, OPENPBR_EPSILON));

        if (dot(wi, wi) <= OPENPBR_EPSILON)
        {
            wi = float3(0.0, 0.0, 0.0);
        }
        else
        {
            wi = OpenPBR_SafeNormalize(wi);
        }
    }

    if (abs(dot(n, wi)) <= OPENPBR_EPSILON || dot(n, v) <= OPENPBR_EPSILON)
    {
        OpenPBRPathResult invalidResult;
        invalidResult.bsdf = float3(0.0, 0.0, 0.0);
        invalidResult.weighted_bsdf = float3(0.0, 0.0, 0.0);
        invalidResult.emission = OpenPBR_EvaluateSurfaceEmission(m, ctx, saturate(dot(coatN, v)));
        invalidResult.continuation_weight = float3(0.0, 0.0, 0.0);
        invalidResult.sample_pdf = 0.0;
        invalidResult.eta = 1.0;
        invalidResult.opacity = ctx.geometry_opacity;
        invalidResult.event_flags = OPENPBR_EVENT_NONE;
        return invalidResult;
    }

    return OpenPBR_EvaluateSurface(m, ctx, wo, wi);
}

#endif
