#ifndef GTRT_COMMON_LIB_INCLUDE
#define GTRT_COMMON_LIB_INCLUDE

SamplerState sampler_LinearRepeat;

float4 _CameraPos;

float4x4 _CameraVPMatrix;
float4x4 _InvCameraVPMatrix;
float4x4 _PrevCameraVPMatrixNoJitter;
float4x4 _PrevInvCameraVPMatrix;

cbuffer UnityPerDraw 
{
    float4x4 unity_ObjectToWorld;
    float4x4 unity_WorldToObject;
    float4 unity_LODFade;
    float4 unity_WorldTransformParams;
}

inline float4 GTRT_ObjectToClipPos(float3 localPos)
{
    float3 absoluteWorldPos = mul(unity_ObjectToWorld, float4(localPos, 1.0)).xyz;
    
    float3 camRelWorldPos = absoluteWorldPos - _CameraPos.xyz;
    
    return mul(_CameraVPMatrix, float4(camRelWorldPos, 1.0));
}

inline float4 GTRT_ObjectToClipPos(float4 localPos)
{
    return GTRT_ObjectToClipPos(localPos.xyz);
}

inline float3 GTRT_ObjectToWorldDir(float3 localDir)
{
    return normalize(mul(localDir, (float3x3)unity_WorldToObject));
}

inline float3 GTRT_ObjectToWorldVec(float3 localVec)
{
    return mul((float3x3)unity_ObjectToWorld, localVec);
}

inline float3 GTRT_ReconstructWorldPos(float2 uv, float depth, float4x4 invVP) 
{
    float4 clipPos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), depth, 1.0);
    float4 worldPos4 = mul(invVP, clipPos);
    return worldPos4.xyz / worldPos4.w;
}

inline float2 GTRT_GetReprojectedHistoryUV(float2 currentUV, float currentDepth) 
{
    float3 worldPos = GTRT_ReconstructWorldPos(currentUV, currentDepth, _InvCameraVPMatrix);
    
    float4 prevClipPos = mul(_PrevCameraVPMatrixNoJitter, float4(worldPos, 1.0));
    float3 prevNDC = prevClipPos.xyz / prevClipPos.w;
    
    return prevNDC.xy * float2(0.5, -0.5) + 0.5;
}

#endif