#ifndef GTRT_SSPTWALKER_INPUTS_INCLUDE
#define GTRT_SSPTWALKER_INPUTS_INCLUDE

#include "../../Lib/CommonLib.hlsl"
//#include "../../Lib/NextUnityShaderLib.hlsl"

#define SSPT_RAY_STATE_NONE        0u
#define SSPT_RAY_STATE_HIT         1u
#define SSPT_RAY_STATE_SKY_MISS    2u
#define SSPT_RAY_STATE_VOLUME_MISS 4u

float4x4 _CameraProjMatrix;
float4x4 _InvCameraViewMatrix;

uint _MaxBounce;
uint _FrameIndex;
uint _AccumulatedFrames;
uint _EnableAccumulation;
uint _MinRussianRouletteBounce;
uint _MaxNullHit;

float _RayTMin;
float _RayTMax;
float _RayOffset;

//----------Begin Skybox----------
float _SkyboxIntensity;
TextureCube<float4> _SkyboxCubemap;
//----------End Skybox----------

//----------Begin DOF----------
float _FocusDistance;
float _ApertureRadius;
uint _LensMode;
float _AnamorphicSqueeze;
int _ApertureNumSides;
float _ApertureAngle;

Texture2D<float> _ApertureMaskTex;
//----------End DOF----------


RaytracingAccelerationStructure _RTAccStruct;

RWTexture2D<float4> rw_OutputRT;



SamplerState sampler_LinearClamp;

#endif
