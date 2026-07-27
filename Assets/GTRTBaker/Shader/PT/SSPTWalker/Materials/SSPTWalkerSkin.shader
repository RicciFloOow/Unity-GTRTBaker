Shader "GTRTBaker/SSPTWalker/SSPTWalkerSkin"
{
    Properties
    {
        _Color("Base Color", Color) = (1, 1, 1, 1)
        _MainTex ("Texture", 2D) = "white" {}
        _NormalTex("Normal Texture", 2D) = "bump" {}
        _Smoothness("Smoothness", Range(0, 1)) = 0.35
        _IOR("IOR", Range(1, 3)) = 1.4
        _SubsurfaceWeight("Subsurface Weight", Range(0, 1)) = 0.6
        _SubsurfaceColor("Subsurface Color", Color) = (1, 0.45, 0.35, 1)
        _SubsurfaceRadius("Subsurface Radius", Float) = 0.01
        _SubsurfaceRadiusScale("Subsurface Radius Scale", Vector) = (1, 0.35, 0.2, 0)
        _SubsurfaceAnisotropy("Subsurface Anisotropy", Range(-0.99, 0.99)) = 0
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

            float4 _Color;
            float _Smoothness;
            float _IOR;
            float _SubsurfaceWeight;
            float4 _SubsurfaceColor;
            float _SubsurfaceRadius;
            float4 _SubsurfaceRadiusScale;
            float _SubsurfaceAnisotropy;
            Texture2D<float4> _MainTex;
            Texture2D<float4> _NormalTex;
            float4 _MainTex_ST;
            float4 _NormalTex_ST;

            #include "../SSPTWalkerInputs.hlsl"
            #include "../SSPTWalkerMeshLib.hlsl"
            #include "../../../Lib/OpenPBR/openpbr_material.hlsl"

            [shader("closesthit")]
            void ClosestHit(inout OpenPBRPayload payload, Attributes attrib)
            {
                VertexAttributes vertex = GetVertexAttributes(attrib);
                float2 mainUV = vertex.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                float2 normalUV = vertex.uv * _NormalTex_ST.xy + _NormalTex_ST.zw;
                float4 albedo = _Color * _MainTex.SampleLevel(sampler_LinearRepeat, mainUV, 0.0);
                float4 normalSample = _NormalTex.SampleLevel(sampler_LinearRepeat, normalUV, 0.0);
                float3 tangentNormal;
                tangentNormal.xy = normalSample.xy * 2.0 - 1.0;
                tangentNormal.z = sqrt(max(1e-4, 1.0 - dot(tangentNormal.xy, tangentNormal.xy)));
                float3 shadingNormal = normalize(
                    tangentNormal.x * vertex.tangentWS +
                    tangentNormal.y * vertex.bitangentWS +
                    tangentNormal.z * vertex.shadingNormal);

                OpenPBRMaterial material = (OpenPBRMaterial)0;
                material.base_weight = 1.0;
                material.base_color = saturate(albedo.xyz);
                material.base_diffuse_roughness = saturate(1.0 - _Smoothness);
                material.specular_weight = 1.0;
                material.specular_color = 1.0;
                material.specular_roughness = max(1e-4, 1.0 - saturate(_Smoothness));
                material.specular_ior = max(_IOR, 1.0);
                material.transmission_weight = saturate(_SubsurfaceWeight);
                material.transmission_color = saturate(_SubsurfaceColor.xyz);
                material.transmission_depth = max(_SubsurfaceRadius, 1e-5);
                material.subsurface_weight = 0.0;
                material.subsurface_color = saturate(_SubsurfaceColor.xyz);
                material.subsurface_radius = max(_SubsurfaceRadius, 1e-5);
                material.subsurface_radius_scale = max(_SubsurfaceRadiusScale.xyz, float3(1e-5, 1e-5, 1e-5));
                material.subsurface_scatter_anisotropy = clamp(_SubsurfaceAnisotropy, -0.99, 0.99);

                OpenPBRSurfaceCtx surfaceCtx = (OpenPBRSurfaceCtx)0;
                surfaceCtx.geometry_opacity = albedo.a;
                surfaceCtx.geometry_thin_walled = false;
                surfaceCtx.geometry_front_face = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;
                surfaceCtx.geometry_normal = vertex.geometryNormal;
                surfaceCtx.shading_normal = shadingNormal;
                surfaceCtx.shading_tangent = vertex.tangentWS;
                surfaceCtx.shading_coat_normal = shadingNormal;
                surfaceCtx.shading_coat_tangent = vertex.tangentWS;
                surfaceCtx.state_flags = OPENPBR_VOLUME_SUBSURFACE;

                payload.rayState = (uint)SSPT_RAY_STATE_HIT;
                payload.tHit = RayTCurrent();
                payload.material = PackOpenPBRMaterial(material);
                payload.surfaceCtx = PackOpenPBRSurfaceContext(surfaceCtx);
            }
            ENDHLSL
        }
    }
}
