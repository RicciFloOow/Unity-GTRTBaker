Shader "GTRTBaker/SSPTWalker/SSPTWalkerOpaque"
{
    Properties
    {
        _Color("Base Color", Color) = (1, 1, 1, 1)
        _MainTex ("Texture", 2D) = "white" {}
        _MetallicTex("Metallic Texture", 2D) = "white" {}
        _Metallic("Metallic", Range(0, 1)) = 0
        [Toggle(GTRT_WORKFLOW_SPECULAR)] _WorkflowSpecular("Specular Workflow", Float) = 0
        _SpecularTex("Specular Texture", 2D) = "white" {}
        _SpecColor("Specular Color", Color) = (1, 1, 1, 1)
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        _NormalTex("Normal Texture", 2D) = "bump" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0, 1)
        _EmissionTex("Emission Texture", 2D) = "white" {}
        _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle] _DoubleSided("Double Sided", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Name "SSPTWalker"
            Tags{ "LightMode" = "HWRayTracing" }

            HLSLPROGRAM

            #pragma raytracing HitShader
            #pragma shader_feature_local GTRT_WORKFLOW_SPECULAR

            float4 _Color;
            float _Metallic;
            float4 _SpecColor;
            float _Smoothness;
            float4 _EmissionColor;
            float _Cutoff;
            float _DoubleSided;
            Texture2D<float4> _MainTex;
            Texture2D<float4> _MetallicTex;
            Texture2D<float4> _SpecularTex;
            Texture2D<float4> _NormalTex;
            Texture2D<float4> _EmissionTex;
            float4 _MainTex_ST;
            float4 _MetallicTex_ST;
            float4 _SpecularTex_ST;
            float4 _NormalTex_ST;
            float4 _EmissionTex_ST;

            #include "../SSPTWalkerInputs.hlsl"
            #include "../SSPTWalkerMeshLib.hlsl"
            #include "../../../Lib/OpenPBR/openpbr_material.hlsl"

            //常规的Opaque的alpha clip不用anyhit来做, 植被等用专门的材质

            [shader("closesthit")]
            void ClosestHit(inout OpenPBRPayload payload, Attributes attrib)
            {
                bool frontFace = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;
                bool doubleSided = _DoubleSided > 0.5;
                if (!doubleSided && !frontFace)
                {
                    OpenPBRSurfaceCtx nullSurfaceCtx = (OpenPBRSurfaceCtx)0;
                    nullSurfaceCtx.geometry_opacity = 0.0;
                    nullSurfaceCtx.geometry_thin_walled = false;
                    nullSurfaceCtx.geometry_front_face = false;
                    nullSurfaceCtx.geometry_normal = float3(0.0, 0.0, 1.0);
                    nullSurfaceCtx.shading_normal = float3(0.0, 0.0, 1.0);
                    nullSurfaceCtx.shading_tangent = float3(1.0, 0.0, 0.0);
                    nullSurfaceCtx.shading_coat_normal = float3(0.0, 0.0, 1.0);
                    nullSurfaceCtx.shading_coat_tangent = float3(1.0, 0.0, 0.0);
                    nullSurfaceCtx.state_flags = OPENPBR_VOLUME_NONE;
                    OpenPBRMaterial nullMaterial = (OpenPBRMaterial)0;

                    payload.rayState = (uint)SSPT_RAY_STATE_HIT;
                    payload.tHit = RayTCurrent();
                    payload.material = PackOpenPBRMaterial(nullMaterial);
                    payload.surfaceCtx = PackOpenPBRSurfaceContext(nullSurfaceCtx);
                    return;
                }

                VertexAttributes vertex = GetVertexAttributes(attrib);
                float2 mainUV = vertex.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                float2 metallicUV = vertex.uv * _MetallicTex_ST.xy + _MetallicTex_ST.zw;
                float2 specularUV = vertex.uv * _SpecularTex_ST.xy + _SpecularTex_ST.zw;
                float2 normalUV = vertex.uv * _NormalTex_ST.xy + _NormalTex_ST.zw;
                float2 emissionUV = vertex.uv * _EmissionTex_ST.xy + _EmissionTex_ST.zw;

                float4 albedo = _Color * _MainTex.SampleLevel(sampler_LinearRepeat, mainUV, 0.0);
                float4 metallicSample = _MetallicTex.SampleLevel(sampler_LinearRepeat, metallicUV, 0.0);
                float4 specularSample = _SpecularTex.SampleLevel(sampler_LinearRepeat, specularUV, 0.0);
                float4 normalSample = _NormalTex.SampleLevel(sampler_LinearRepeat, normalUV, 0.0);
                float3 tangentNormal;
                tangentNormal.xy = normalSample.xy * 2.0 - 1.0;
                tangentNormal.z = sqrt(max(1e-4, 1.0 - dot(tangentNormal.xy, tangentNormal.xy)));
                float3 shadingNormal = normalize(
                    tangentNormal.x * vertex.tangentWS +
                    tangentNormal.y * vertex.bitangentWS +
                    tangentNormal.z * vertex.shadingNormal);

#if defined(GTRT_WORKFLOW_SPECULAR)
                float3 specularColor = saturate(_SpecColor.xyz * specularSample.xyz);
                float finalSmoothness = saturate(_Smoothness * specularSample.a);
                float metalness = 0.0;
#else
                float3 specularColor = 1.0;
                float finalSmoothness = saturate(_Smoothness * metallicSample.a);
                float metalness = saturate(_Metallic * metallicSample.r);
#endif

                OpenPBRMaterial material = (OpenPBRMaterial)0;
                material.base_weight = 1.0;
                material.base_color = saturate(albedo.xyz);
                material.base_metalness = metalness;
                material.base_diffuse_roughness = saturate(1.0 - finalSmoothness);
                material.specular_weight = 1.0;
                material.specular_color = specularColor;
                material.specular_roughness = max(1e-4, 1.0 - finalSmoothness);
                material.specular_ior = 1.5;
                material.emission_luminance = 1.0;
                material.emission_color = _EmissionColor.xyz * _EmissionTex.SampleLevel(sampler_LinearRepeat, emissionUV, 0.0).xyz;

                OpenPBRSurfaceCtx surfaceCtx = (OpenPBRSurfaceCtx)0;
                surfaceCtx.geometry_opacity = albedo.a >= _Cutoff ? 1.0 : 0.0;
                surfaceCtx.geometry_thin_walled = false;
                surfaceCtx.geometry_front_face = frontFace || doubleSided;
                surfaceCtx.geometry_normal = vertex.geometryNormal;
                surfaceCtx.shading_normal = shadingNormal;
                surfaceCtx.shading_tangent = vertex.tangentWS;
                surfaceCtx.shading_coat_normal = shadingNormal;
                surfaceCtx.shading_coat_tangent = vertex.tangentWS;
                surfaceCtx.state_flags = OPENPBR_VOLUME_NONE;

                payload.rayState = (uint)SSPT_RAY_STATE_HIT;
                payload.tHit = RayTCurrent();
                payload.material = PackOpenPBRMaterial(material);
                payload.surfaceCtx = PackOpenPBRSurfaceContext(surfaceCtx);
            }
            ENDHLSL
        }
    }
}
