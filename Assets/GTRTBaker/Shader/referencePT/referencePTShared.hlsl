//ref: https://github.com/boksajak/referencePT/blob/master/shaders/shared.h
#ifndef GTRT_REFERENCEPT_SHARED_INCLUDE
#define GTRT_REFERENCEPT_SHARED_INCLUDE

#define POINT_LIGHT 1
#define DIRECTIONAL_LIGHT 2

// Conversion between linear and sRGB color spaces
inline float linearToSrgb(float linearColor)
{
	if (linearColor < 0.0031308f) return linearColor * 12.92f;
	else return 1.055f * float(pow(linearColor, 1.0f / 2.4f)) - 0.055f;
}

inline float srgbToLinear(float srgbColor)
{
	if (srgbColor < 0.04045f) return srgbColor / 12.92f;
	else return float(pow((srgbColor + 0.055f) / 1.055f, 2.4f));
}

struct Light 
{
	float3 position;
	uint type;
	float3 intensity;
	uint pad;
};

//由于unity中dxr的底层的资源绑定是黑盒, 没法用全局的bindless的. 
//既然是基于local root signature的那就不用什么材质id啥的了, payload中直接传获取到的属性
struct HitInfo
{
	float4 encodedNormals;
	float3 hitPosition;
	
	float3 baseColor;
	float3 emissive;
	float roughness;
	float metalness;

	bool hasHit;
};

//cbuffer data:
float4x4 _CameraViewMatrix;
float4x4 _InvCameraViewMatrix;
float4x4 _CameraProjMatrix;
float4 _CameraPos;

float _SkyIntensity;
uint _FrameNumber;
uint _MaxBounces;

float _ExposureAdjustment;
uint _AccumulatedFrames;
bool _EnableAntiAliasing;
float _FocusDistance;

float _ApertureSize;
bool _EnableAccumulation;

//light相关: 绕过4盏灯的限制
float3 _SceneBoundsMin;
float3 _Subdivisions;
float3 _LightChunkSize;

StructuredBuffer<Light> _LightDatasBuffer;
StructuredBuffer<int> _FlattenedLightIndicesBuffer;
StructuredBuffer<int2> _ChunkOffsetsBuffer;

#endif