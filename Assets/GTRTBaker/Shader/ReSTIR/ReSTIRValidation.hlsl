#ifndef GTRT_RESTIR_VALIDATION_INCLUDE
#define GTRT_RESTIR_VALIDATION_INCLUDE

#include "../Lib/CommonLib.hlsl"

struct SurfaceContext
{
    int instanceID;
    int primitiveID;
};

bool IsValidHistoryPixel(SurfaceContext current, SurfaceContext history) 
{
    return (current.instanceID == history.instanceID);
    //return (current.instanceID == history.instanceID) && (current.primitiveID == history.primitiveID);//@TODO: 配合primitiveID反而有问题——导致"断层"
}

bool FindValidHistoryUVIn2x2(float2 currentUV, float currentDepth, float3 currentWorldPos,
    Texture2D<int2> historyIDMap, Texture2D<float> historyDepthMap,
    float4 hisTexSize, SurfaceContext currentSurface,
    out float2 outValidUV)
{
    float2 baseHistoryUV = GTRT_GetReprojectedHistoryUV(currentUV, currentDepth);
    
    float2 pixelPos = baseHistoryUV * hisTexSize.xy;
    
    float2 basePixel = floor(pixelPos - 0.5);
    
    bool foundMatch = false;
    float minWorldDistanceSq = 1e12;
    float2 bestUV = baseHistoryUV;
    
    [unroll]
    for (int y = 0; y <= 1; y++) 
    {
        [unroll]
        for (int x = 0; x <= 1; x++) 
        {
            int2 currentPixel = basePixel + int2(x, y);
            
            if (any(currentPixel < 0) || any(currentPixel >= (int2)hisTexSize.xy))
                continue;
                
            int2 histID = historyIDMap.Load(int3(currentPixel, 0));
            
            SurfaceContext historySurface;
            historySurface.instanceID = histID.x;
            historySurface.primitiveID = histID.y;
            
            if (IsValidHistoryPixel(currentSurface, historySurface)) 
            {
                float histDepth = historyDepthMap.Load(int3(currentPixel, 0));
                
                float2 offsetUV = (currentPixel + 0.5) * hisTexSize.zw;
                
                float3 histWorldPos = GTRT_ReconstructWorldPos(offsetUV, histDepth, _PrevInvCameraVPMatrix);
                
                float3 diff = histWorldPos - currentWorldPos;
                float worldDistSq = dot(diff, diff);
                
                if (worldDistSq < minWorldDistanceSq) 
                {
                    minWorldDistanceSq = worldDistSq;
                    bestUV = offsetUV;
                    foundMatch = true;
                }
            }
        }
    }
    
    outValidUV = bestUV;
    return foundMatch;
}
    
#endif