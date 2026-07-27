#ifndef GTRT_SS_RTAO_LIB_INCLUDE
#define GTRT_SS_RTAO_LIB_INCLUDE

#include "UnityRayQuery.cginc"

uint _FrameIndex;

float _AORadius;

RaytracingAccelerationStructure _RTAccStruct;

Texture2D<float> _CamDepthTexture;
Texture2D<float4> _CamNormalsTexture;
RWTexture2D<float4> rw_OutputRT;


#endif