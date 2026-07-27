Shader "GTRTBaker/referencePT/referencePTOpaque"
{
    Properties
    {
        _Color("Base Color", Color) = (1, 1, 1, 1)
        _MainTex ("Texture", 2D) = "white" {}

        _MetallicTex ("Metallic Texture", 2D) = "white" {}
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        
        _SpecularTex ("Specular Texture", 2D) = "white" {}
        _SpecColor ("Specular Color", Color) = (0.2, 0.2, 0.2, 1)
        
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _NormalTex ("Normal Texture", 2D) = "bump" {}

        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)
        _EmissionTex ("Emission Texture", 2D) = "white" {}

        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            Name "referencePT"
            Tags{ "LightMode" = "HWRayTracing" }

            HLSLPROGRAM

            #pragma raytracing HitShader

            float4 _Color;
            float  _Metallic;
            float4 _SpecColor;
            float  _Smoothness;
            float4 _EmissionColor;
            float  _Cutoff;
            Texture2D<float4> _MainTex;
            Texture2D<float4> _NormalTex;
            Texture2D<float4> _MetallicTex;
            Texture2D<float4> _SpecularTex;
            Texture2D<float4> _EmissionTex;

            #include "referencePTPathTracer.hlsl"

            [shader("anyhit")]
            void AnyHit(inout HitInfo payload : SV_RayPayload, Attributes attrib : SV_IntersectionAttributes)
            {
                if (testOpacityAnyHit(attrib, _Cutoff, _MainTex)) 
                {
                    IgnoreHit();
                }
            }

            [shader("closesthit")]
            void ClosestHit(inout HitInfo payload, Attributes attrib)
            {
                VertexAttributes vertex = GetVertexAttributes(attrib);

                float4 normalSample = _NormalTex.SampleLevel(sampler_LinearRepeat, vertex.uv, 0);
                float3 tangentNormal;
                tangentNormal.xy = normalSample.xy * 2.0 - 1.0;
                tangentNormal.z = sqrt(max(0.0001, 1.0 - dot(tangentNormal.xy, tangentNormal.xy)));

                float3x3 tbn = float3x3(vertex.tangentWS, vertex.bitangentWS, vertex.shadingNormal);
                float3 perturbedNormal = normalize(mul(tangentNormal, tbn));

                payload.encodedNormals = encodeNormals(vertex.geometryNormal, perturbedNormal);
                payload.hitPosition = vertex.position;

                payload.baseColor = _Color.xyz * _MainTex.SampleLevel(sampler_LinearRepeat, vertex.uv, 0).xyz;
                payload.emissive = _EmissionColor.xyz * _EmissionTex.SampleLevel(sampler_LinearRepeat, vertex.uv, 0).xyz;
                
                
                float4 metallicSample = _MetallicTex.SampleLevel(sampler_LinearRepeat, vertex.uv, 0);
                payload.metalness = _Metallic * metallicSample.x;
                float finalSmoothness = _Smoothness * metallicSample.w;
                payload.roughness = max(1e-5, 1.0 - finalSmoothness);

                payload.hasHit = true;
            }

            ENDHLSL
        }
    }
}
