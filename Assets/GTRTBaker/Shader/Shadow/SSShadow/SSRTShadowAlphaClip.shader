Shader "GTRTBaker/Shadow/SSRTShadowAlphaClip"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        _MetallicTex ("Metallic Texture", 2D) = "white" {}
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        
        _SpecularTex ("Specular Texture", 2D) = "white" {}
        _SpecColor ("Specular Color", Color) = (0.2, 0.2, 0.2, 1)
        
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _NormalTex ("Normal Texture", 2D) = "bump" {}

        _EmissionColor ("Emission Color", Vector) = (0, 0, 0, 1)

        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _RendererInstanceID ("Object ID", Integer) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma shader_feature_local GTRT_WORKFLOW_SPECULAR
            #pragma shader_feature_local GTRT_ALPHA_CLIP

            #include "../../Lib/CommonLib.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct RTGbuffer
            {
                float4 normal   : SV_Target0;
                float4 material : SV_Target1;
                int2 topologyID : SV_Target2;
            };

            Texture2D<float4> _MainTex;
            Texture2D<float4> _NormalTex;
            Texture2D<float4> _MetallicTex;
            Texture2D<float4> _SpecularTex;

            cbuffer UnityPerMaterial
            {
                float4 _MainTex_ST;
                float4 _Color;
                float  _Metallic;
                float4 _SpecColor;
                float  _Smoothness;
                float4 _EmissionColor;
                float _Cutoff;
                int _RendererInstanceID;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = GTRT_ObjectToClipPos(v.vertex);
                o.uv = v.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                o.normal = GTRT_ObjectToWorldDir(v.normal);
                o.tangent.xyz = GTRT_ObjectToWorldVec(v.tangent.xyz);
                o.tangent.w = v.tangent.w * unity_WorldTransformParams.x;
                return o;
            }

            RTGbuffer frag (v2f i, uint primitiveID : SV_PrimitiveID)
            {
                float2 uv = i.uv;

#if defined(GTRT_ALPHA_CLIP)
                float alpha = _MainTex.Sample(sampler_LinearRepeat, uv).a;
                clip(alpha - _Cutoff);
#endif
                RTGbuffer gbuffer = (RTGbuffer)0;

                float3 N = normalize(i.normal);
                float3 T = normalize(i.tangent.xyz);
                float3 B = cross(N, T) * i.tangent.w;
                float3 normal = _NormalTex.Sample(sampler_LinearRepeat, uv).xyz * 2.0 - 1.0;
                
                normal = normalize(normal.x * T + normal.y * B + normal.z * N);
                gbuffer.normal = float4(normalize(normal), 1);

                float luminance = dot(_EmissionColor.xyz, float3(0.2126, 0.7152, 0.0722));
                float isLightSource = luminance > 0 ? 1 : 0;
                float smoothness = _Smoothness;
                float specularProb = 0.0;
#if defined(GTRT_WORKFLOW_SPECULAR)
                float4 specSample = _SpecularTex.Sample(sampler_LinearRepeat, uv);
                float3 spec = specSample.xyz * _SpecColor.xyz;
                smoothness *= specSample.w;
                specularProb = saturate(dot(spec, float3(0.2126, 0.7152, 0.0722)));
#else
                float4 metalSample = _MetallicTex.Sample(sampler_LinearRepeat, uv);
                float metal = metalSample.x * _Metallic;
                smoothness *= metalSample.w;
                specularProb = lerp(0.04, 1.0, metal);
#endif
                gbuffer.material = float4(specularProb, isLightSource, 0, smoothness);
                gbuffer.topologyID = int2(_RendererInstanceID, (int)primitiveID);
                return gbuffer;
            }
            ENDHLSL
        }

        Pass
        {
            Name "SSRTShadow"
            Tags{ "LightMode" = "HWRayTracing" }

            HLSLPROGRAM

            #pragma raytracing HitShader

            float4 _EmissionColor;
            float  _Cutoff;
            Texture2D<float4> _MainTex;

            #define UNITY_DXR
            #include "SSRTShadowLib.hlsl"

            SamplerState sampler_LinearRepeat;

            [shader("anyhit")]
            void AnyHit(inout HitInfo payload : SV_RayPayload, Attributes attrib : SV_IntersectionAttributes)
            {
                if (!payload.isRayOcc)
                {
                    float luminance = dot(_EmissionColor.xyz, float3(0.2126, 0.7152, 0.0722));
        
                    if (luminance <= 0.0) 
                    {
                        IgnoreHit();
                        return;
                    }
                }

                IntersectionVertex vertex = GetVertexAttributes(attrib);
	
	            float alpha = _MainTex.SampleLevel(sampler_LinearRepeat, vertex.texCoord0, 0.0f).w;

	            if (alpha < _Cutoff) 
                {
                    IgnoreHit();
                }
            }

            [shader("closesthit")]
            void ClosestHit(inout HitInfo payload, Attributes attrib)
            {
                float luminance = dot(_EmissionColor.xyz, float3(0.2126, 0.7152, 0.0722));

                payload.hitEmission = luminance;
            }
            ENDHLSL
        }
    }
}
