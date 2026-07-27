Shader "GTRTBaker/SSPTWalker/SSPTWalkerGlass"
{
    Properties
    {
        _Color("Base Color", Color) = (1, 1, 1, 1)
        _Smoothness("Smoothness", Range(0, 1)) = 1
        _IOR("IOR", Range(1, 3)) = 1.5
        _TransmissionColor("Transmission Color", Color) = (1, 1, 1, 1)
        _TransmissionDepth("Transmission Depth", Float) = 1
        _TransmissionScatter("Transmission Scatter", Color) = (0, 0, 0, 1)
        _TransmissionScatterAnisotropy("Transmission Anisotropy", Range(-0.99, 0.99)) = 0
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0, 1)
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
            float4 _TransmissionColor;
            float _TransmissionDepth;
            float4 _TransmissionScatter;
            float _TransmissionScatterAnisotropy;
            float4 _EmissionColor;

            #include "../SSPTWalkerInputs.hlsl"
            #include "../SSPTWalkerMeshLib.hlsl"
            #include "../../../Lib/OpenPBR/openpbr_material.hlsl"

            [shader("closesthit")]
            void ClosestHit(inout OpenPBRPayload payload, Attributes attrib)
            {
                VertexAttributes vertex = GetVertexAttributes(attrib);

                OpenPBRMaterial material = (OpenPBRMaterial)0;
                material.base_weight = 1.0;
                material.base_color = saturate(_Color.xyz);
                material.specular_weight = 1.0;
                material.specular_color = 1.0;
                material.specular_roughness = max(1e-4, 1.0 - saturate(_Smoothness));
                material.specular_ior = max(_IOR, 1.0);
                material.transmission_weight = 1.0;
                material.transmission_color = saturate(_TransmissionColor.xyz * _Color.xyz);
                material.transmission_depth = max(_TransmissionDepth, 0.0);
                material.transmission_scatter = saturate(_TransmissionScatter.xyz);
                material.transmission_scatter_anisotropy = clamp(_TransmissionScatterAnisotropy, -0.99, 0.99);
                material.emission_luminance = 1.0;
                material.emission_color = _EmissionColor.xyz;

                OpenPBRSurfaceCtx surfaceCtx = (OpenPBRSurfaceCtx)0;
                surfaceCtx.geometry_opacity = 1.0;
                surfaceCtx.geometry_thin_walled = false;
                surfaceCtx.geometry_front_face = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;
                surfaceCtx.geometry_normal = vertex.geometryNormal;
                surfaceCtx.shading_normal = vertex.shadingNormal;
                surfaceCtx.shading_tangent = vertex.tangentWS;
                surfaceCtx.shading_coat_normal = vertex.shadingNormal;
                surfaceCtx.shading_coat_tangent = vertex.tangentWS;
                surfaceCtx.state_flags = OPENPBR_VOLUME_TRANSMISSION;

                payload.rayState = (uint)SSPT_RAY_STATE_HIT;
                payload.tHit = RayTCurrent();
                payload.material = PackOpenPBRMaterial(material);
                payload.surfaceCtx = PackOpenPBRSurfaceContext(surfaceCtx);
            }
            ENDHLSL
        }
    }
}
