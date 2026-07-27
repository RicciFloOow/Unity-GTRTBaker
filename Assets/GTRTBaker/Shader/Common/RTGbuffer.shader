Shader "GTRTBaker/Common/RTGbuffer"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Albedo Color", Color) = (1, 1, 1, 1)

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
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile GTRT_BAKE_FULL GTRT_BAKE_NORMAL

            #pragma shader_feature_local GTRT_WORKFLOW_SPECULAR
            #pragma shader_feature_local GTRT_EMISSION
            #pragma shader_feature_local GTRT_ALPHA_CLIP

            #include "../Lib/CommonLib.hlsl"

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
#if defined(GTRT_BAKE_NORMAL)
                float4 normal   : SV_Target0;
#else
                float4 albedo   : SV_Target0;
                float4 normal   : SV_Target1;
                float4 material : SV_Target2;
                float4 emission : SV_Target3;
#endif
            };

            Texture2D<float4> _MainTex;
            Texture2D<float4> _NormalTex;
            Texture2D<float4> _MetallicTex;
            Texture2D<float4> _SpecularTex;
            Texture2D<float4> _EmissionTex;

            cbuffer UnityPerMaterial
            {
                float4 _MainTex_ST;
                float4 _Color;
                float  _Metallic;
                float4 _SpecColor;
                float  _Smoothness;
                float4 _EmissionColor;
                float _Cutoff;
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

            RTGbuffer frag (v2f i)
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

#if defined(GTRT_BAKE_FULL)
                gbuffer.albedo = _MainTex.Sample(sampler_LinearRepeat, uv) * _Color;
                    
                float smoothness = _Smoothness;
#if defined(GTRT_WORKFLOW_SPECULAR)
                float4 specSample = _SpecularTex.Sample(sampler_LinearRepeat, uv);
                float3 spec = specSample.xyz * _SpecColor.xyz;
                smoothness *= specSample.w;
                gbuffer.material = float4(spec, smoothness);
#else
                float4 metalSample = _MetallicTex.Sample(sampler_LinearRepeat, uv);
                float metal = metalSample.x * _Metallic;
                smoothness *= metalSample.w;
                gbuffer.material = float4(metal, 0.0, 0.0, smoothness);
#endif

#if defined(GTRT_EMISSION)
                float3 em = _EmissionTex.Sample(sampler_LinearRepeat, uv).xyz * _EmissionColor.xyz;
                gbuffer.emission = float4(em, 1.0);
#else
                gbuffer.emission = float4(0, 0, 0, 1);
#endif
#endif

                return gbuffer;
            }
            ENDHLSL
        }
    }
}
