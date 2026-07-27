Shader "GTRTBaker/SSPTWalker/SSPTWalkerDeepTissue"
{
    Properties
    {
        _Color("Tissue Color", Color) = (0.45, 0.08, 0.045, 1)
        _MainTex("Texture", 2D) = "white" {}
        _NormalTex("Normal Texture", 2D) = "bump" {}
        _Smoothness("Smoothness", Range(0, 1)) = 0.15
        _SpecularWeight("Specular Weight", Range(0, 1)) = 0.25
        _IOR("IOR", Range(1, 3)) = 1.38
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
            float _SpecularWeight;
            float _IOR;
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
                material.specular_weight = saturate(_SpecularWeight);
                material.specular_color = 1.0;
                material.specular_roughness = max(1e-4, 1.0 - saturate(_Smoothness));
                material.specular_ior = max(_IOR, 1.0);

                OpenPBRSurfaceCtx surfaceCtx = (OpenPBRSurfaceCtx)0;
                surfaceCtx.geometry_opacity = 1.0;
                surfaceCtx.geometry_thin_walled = false;
                surfaceCtx.geometry_front_face = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;
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
