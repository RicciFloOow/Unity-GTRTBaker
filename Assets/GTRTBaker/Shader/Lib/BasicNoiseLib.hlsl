//ref: https://developer.nvidia.com/ray-tracing-gems-ii
#ifndef GTRT_BASIC_NOISE_LIB_INCLUDE
#define GTRT_BASIC_NOISE_LIB_INCLUDE

#define FLT_EPSILON     1.192092896e-07
#define TWO_PI          6.28318530718
#define INV_PI          0.31830988618

float2 MapToUnitDisk(float2 u)
{
    float r = sqrt(u.x);
    float theta = TWO_PI * u.y;
    return r * float2(cos(theta), sin(theta));
}

float3 MapToUniformHemisphere(float2 u)
{
    float z = u.x;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = TWO_PI * u.y;
    return float3(r * cos(phi), r * sin(phi), z);
}

float3 MapToCosineHemisphere(float2 u)
{
    float2 disk = MapToUnitDisk(u);
    float z = sqrt(max(0.0, 1.0 - dot(disk, disk)));
    return float3(disk.x, disk.y, z);
}

float3 MapToUniformSphere(float2 u)
{
    float z = 1.0 - 2.0 * u.x;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = TWO_PI * u.y;
    return float3(r * cos(phi), r * sin(phi), z);
}

//ref: https://www.jcgt.org/published/0006/01/01/paper-lowres.pdf
void BuildOrthonormalBasis(float3 n, out float3 b1, out float3 b2)
{
    float sign = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sign + n.z);
    float b = n.x * n.y * a;
    b1 = float3(1.0 + sign * n.x * n.x * a, sign * b, -sign * n.x);
    b2 = float3(b, sign + n.y * n.y * a, -n.y);
}

//ref: https://www.pcg-random.org/
float pcgHash(inout uint state)
{
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    word = (word >> 22u) ^ word;
    return word / 4294967295.0;
}

float2 pcgHash2D(inout uint state)
{
    return float2(pcgHash(state), pcgHash(state));
}

//ref: https://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
//不行可以用web.archive.org查看快照
float2 GetScrambledR4Sequence(uint sampleIndex, float2 scramble)
{
    const float a3 = 0.6287339746401614f;
    const float a4 = 0.5386415441315995f;
    
    float2 basePoint = frac(float2(a3, a4) * float(sampleIndex));
    
    return frac(basePoint + scramble);
}

float3 GetR4CosineHemisphereDirectionWorld(float3 worldNormal, uint sampleIndex, float2 pixelScramble)
{
    float2 R4Point = GetScrambledR4Sequence(sampleIndex, pixelScramble);

    float3 localDir = MapToCosineHemisphere(R4Point);

    float3 tangent, bitangent;
    BuildOrthonormalBasis(worldNormal, tangent, bitangent);
    
    return normalize(tangent * localDir.x + bitangent * localDir.y + worldNormal * localDir.z);
}

float3 GetR4UniformHemisphereDirectionWorld(float3 worldNormal, uint sampleIndex, float2 pixelScramble)
{
    float2 R4Point = GetScrambledR4Sequence(sampleIndex, pixelScramble);
    float3 localDir = MapToUniformHemisphere(R4Point);
    
    float3 tangent, bitangent;
    BuildOrthonormalBasis(worldNormal, tangent, bitangent);
    
    return normalize(tangent * localDir.x + bitangent * localDir.y + worldNormal * localDir.z);
}

float3 GetR4UniformSphereDirectionWorld(uint sampleIndex, float2 pixelScramble)
{
    float2 R4Point = GetScrambledR4Sequence(sampleIndex, pixelScramble);
    return MapToUniformSphere(R4Point);
}

#endif