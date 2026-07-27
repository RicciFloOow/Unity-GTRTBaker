using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    [Serializable]
    public struct SSPTWalkerSettings
    {
        public int MaxBounce;
        public bool EnableAccumulation;

        public Cubemap SkyboxCubemap;
        public float SkyboxIntensity;

        public float RayTMin;
        public float RayTMax;
        public float RayOffset;
        public int MaxNullHit;
        public int MinRussianRouletteBounce;

        public float FocusDistance;
        public float ApertureRadius;
        public int LensMode;
        public int ApertureNumSides;
        public float ApertureAngle;
        public float AnamorphicSqueeze;
        public Texture2D ApertureMaskTex;

        public LayerMask LayerMask;
        public bool LogRejectedRenderers;

        public static SSPTWalkerSettings Default => new SSPTWalkerSettings
        {
            MaxBounce = 8,
            EnableAccumulation = true,
            SkyboxCubemap = null,
            SkyboxIntensity = 1.0f,
            RayTMin = 1e-5f,
            RayTMax = 1e5f,
            RayOffset = 1e-5f,
            MaxNullHit = 32,
            MinRussianRouletteBounce = 3,
            FocusDistance = 10.0f,
            ApertureRadius = 0.0f,
            LensMode = 0,
            ApertureNumSides = 6,
            ApertureAngle = 0.0f,
            AnamorphicSqueeze = 1.0f,
            ApertureMaskTex = null,
            LayerMask = ~0,
            LogRejectedRenderers = true
        };
    }

    public sealed class SSPTWalkerRendererFilter : ISceneBakerRendererFilter
    {
        private static readonly string[] k_DefaultAllowedShaderNames =
        {
            "GTRTBaker/SSPTWalker/SSPTWalkerOpaque",
            "GTRTBaker/SSPTWalker/SSPTWalkerGlass",
            "GTRTBaker/SSPTWalker/SSPTWalkerSkin",
            "GTRTBaker/SSPTWalker/SSPTWalkerDeepTissue"
        };

        private readonly HashSet<Shader> m_allowedShaders = new HashSet<Shader>();
        private readonly LayerMask m_layerMask;

        public SSPTWalkerRendererFilter(LayerMask layerMask)
            : this(layerMask, null)
        {
        }

        public SSPTWalkerRendererFilter(LayerMask layerMask, IEnumerable<Shader> allowedShaders)
        {
            m_layerMask = layerMask;

            if (allowedShaders != null)
            {
                foreach (var shader in allowedShaders)
                {
                    if (shader != null)
                        m_allowedShaders.Add(shader);
                }
            }

            if (m_allowedShaders.Count == 0)
            {
                for (int i = 0; i < k_DefaultAllowedShaderNames.Length; i++)
                {
                    var shader = Shader.Find(k_DefaultAllowedShaderNames[i]);
                    if (shader != null)
                        m_allowedShaders.Add(shader);
                }
            }
        }

        public bool IsValid(Renderer renderer, out string reason)
        {
            reason = null;

            if (renderer == null)
            {
                reason = "renderer is null";
                return false;
            }

            if (!renderer.gameObject.activeInHierarchy || !renderer.enabled)
            {
                return false;
            }

            int rendererLayerMask = 1 << renderer.gameObject.layer;
            if ((m_layerMask.value & rendererLayerMask) == 0)
            {
                return false;
            }

            if (!(renderer is MeshRenderer) && !(renderer is SkinnedMeshRenderer))
            {
                reason = "renderer type is not supported";
                return false;
            }

            var materials = renderer.sharedMaterials;
            if (materials == null || materials.Length == 0)
            {
                reason = "renderer has no materials";
                return false;
            }

            if (materials.Length > 32)
            {
                reason = $"renderer has {materials.Length} materials, exceeding the DXR per-instance limit of 32";
                return false;
            }

            for (int i = 0; i < materials.Length; i++)
            {
                var material = materials[i];
                if (material == null)
                {
                    reason = $"material {i} is null";
                    return false;
                }

                if (material.shader == null || !m_allowedShaders.Contains(material.shader))
                {
                    reason = $"material {i} uses unsupported shader {material.shader?.name ?? "<null>"}";
                    return false;
                }
            }

            return true;
        }
    }

    public class ScreenSpacePTWalkerBaker : BaseBaker
    {
        public RenderTextureHandle OutputHandle => m_outputHandle;

        #region ----Properties----
        private readonly RayTracingShader m_rts;
        private readonly Camera m_camera;
        private readonly SSPTWalkerSettings m_settings;
        private readonly ISceneBakerRendererFilter m_rendererFilter;

        private RayTracingAccelerationStructure m_rtas;
        private List<Renderer> m_validRenderers;

        private bool m_ownsOutputHandle;
        private RenderTextureHandle m_outputHandle;
        private Cubemap m_fallbackSkyboxCubemap;
        #endregion

        #region ----Constants----
        private static readonly RayTracingSubMeshFlags[] k_rtSubMeshFlags = new RayTracingSubMeshFlags[]
        {
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled,
            RayTracingSubMeshFlags.Enabled
        };

        private static readonly int k_ShaderProperty_CameraPos = Shader.PropertyToID("_CameraPos");
        private static readonly int k_ShaderProperty_CameraProjMatrix = Shader.PropertyToID("_CameraProjMatrix");
        private static readonly int k_ShaderProperty_InvCameraViewMatrix = Shader.PropertyToID("_InvCameraViewMatrix");
        private static readonly int k_ShaderProperty_MaxBounce = Shader.PropertyToID("_MaxBounce");
        private static readonly int k_ShaderProperty_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int k_ShaderProperty_AccumulatedFrames = Shader.PropertyToID("_AccumulatedFrames");
        private static readonly int k_ShaderProperty_EnableAccumulation = Shader.PropertyToID("_EnableAccumulation");
        private static readonly int k_ShaderProperty_MinRussianRouletteBounce = Shader.PropertyToID("_MinRussianRouletteBounce");
        private static readonly int k_ShaderProperty_MaxNullHit = Shader.PropertyToID("_MaxNullHit");
        private static readonly int k_ShaderProperty_RayTMin = Shader.PropertyToID("_RayTMin");
        private static readonly int k_ShaderProperty_RayTMax = Shader.PropertyToID("_RayTMax");
        private static readonly int k_ShaderProperty_RayOffset = Shader.PropertyToID("_RayOffset");
        private static readonly int k_ShaderProperty_SkyboxIntensity = Shader.PropertyToID("_SkyboxIntensity");
        private static readonly int k_ShaderProperty_SkyboxCubemap = Shader.PropertyToID("_SkyboxCubemap");
        private static readonly int k_ShaderProperty_FocusDistance = Shader.PropertyToID("_FocusDistance");
        private static readonly int k_ShaderProperty_ApertureRadius = Shader.PropertyToID("_ApertureRadius");
        private static readonly int k_ShaderProperty_LensMode = Shader.PropertyToID("_LensMode");
        private static readonly int k_ShaderProperty_AnamorphicSqueeze = Shader.PropertyToID("_AnamorphicSqueeze");
        private static readonly int k_ShaderProperty_ApertureNumSides = Shader.PropertyToID("_ApertureNumSides");
        private static readonly int k_ShaderProperty_ApertureAngle = Shader.PropertyToID("_ApertureAngle");
        private static readonly int k_ShaderProperty_ApertureMaskTex = Shader.PropertyToID("_ApertureMaskTex");
        private static readonly int k_ShaderProperty_RTAccStruct = Shader.PropertyToID("_RTAccStruct");
        private static readonly int k_ShaderProperty_rw_OutputRT = Shader.PropertyToID("rw_OutputRT");
        #endregion

        #region ----Constructor----
        public ScreenSpacePTWalkerBaker(RayTracingShader rts, Camera camera, SSPTWalkerSettings settings, RenderTextureHandle outputHandle = null, ISceneBakerRendererFilter rendererFilter = null)
        {
            m_rts = rts;
            m_camera = camera;
            m_settings = settings;
            m_outputHandle = outputHandle;
            m_rendererFilter = rendererFilter ?? new SSPTWalkerRendererFilter(settings.LayerMask);
        }

        public ScreenSpacePTWalkerBaker(RayTracingShader rts, Camera camera, RenderTextureHandle outputHandle = null)
            : this(rts, camera, SSPTWalkerSettings.Default, outputHandle)
        {
        }
        #endregion

        private void SetupRTHandles()
        {
            if (m_outputHandle != null)
                return;

            m_ownsOutputHandle = true;
            m_outputHandle = new RenderTextureHandle(new RTDesc(m_camera.pixelWidth, m_camera.pixelHeight, GraphicsFormat.R32G32B32A32_SFloat, true));
            m_outputHandle.SetName("SSPTWalker_Output");
        }

        private void ReleaseRTHandles()
        {
            if (m_ownsOutputHandle)
                m_outputHandle?.Dispose();

            m_outputHandle = null;
            m_ownsOutputHandle = false;
        }

        private Cubemap GetSkyboxCubemap()
        {
            if (m_settings.SkyboxCubemap != null)
                return m_settings.SkyboxCubemap;

            if (m_fallbackSkyboxCubemap == null)
            {
                m_fallbackSkyboxCubemap = new Cubemap(1, TextureFormat.RGBA32, false)
                {
                    name = "SSPTWalker_BlackSkybox"
                };

                Color[] black = { Color.black };
                for (int i = 0; i < 6; i++)
                {
                    m_fallbackSkyboxCubemap.SetPixels(black, (CubemapFace)i);
                }
                m_fallbackSkyboxCubemap.Apply(false, true);
            }

            return m_fallbackSkyboxCubemap;
        }

        public override void Preprocess(BakeContext context)
        {
            if (m_rts == null || m_camera == null)
            {
                Debug.LogError("[GTRTBaker] ScreenSpacePTWalkerBaker requires a ray tracing shader and a camera.");
                return;
            }

            SetupRTHandles();
            m_validRenderers = SceneCollectUtilities.CollectRenderers(m_rendererFilter, m_settings.LogRejectedRenderers);

            var rtasSettings = new RayTracingAccelerationStructure.Settings
            {
                managementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
                rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything,
                layerMask = -1
            };

            m_rtas = new RayTracingAccelerationStructure(rtasSettings);
            if (m_validRenderers != null)
            {
                for (int i = 0; i < m_validRenderers.Count; i++)
                {
                    var renderer = m_validRenderers[i];
                    if (renderer != null)
                        m_rtas.AddInstance(renderer, k_rtSubMeshFlags);
                }
            }

            m_rtas.Build(m_camera.transform.position);
        }

        public override void Setup(BakeContext context, CommandBuffer cmd)
        {
        }

        public override void BuildStepCommand(BakeContext context, CommandBuffer cmd)
        {
            if (m_rts == null || m_camera == null || m_rtas == null || m_outputHandle == null)
                return;

            int frameIndex = context.CurrentSPP + 1;

            Matrix4x4 cameraViewMatrix = m_camera.transform.worldToLocalMatrix;
            cameraViewMatrix.SetColumn(3, new Vector4(0, 0, 0, 1.0f));
            Matrix4x4 invCameraViewMatrix = cameraViewMatrix.inverse;
            Matrix4x4 cameraProjMatrix = GL.GetGPUProjectionMatrix(m_camera.projectionMatrix, true);

            cmd.SetRayTracingVectorParam(m_rts, k_ShaderProperty_CameraPos, m_camera.transform.position);
            cmd.SetRayTracingMatrixParam(m_rts, k_ShaderProperty_CameraProjMatrix, cameraProjMatrix);
            cmd.SetRayTracingMatrixParam(m_rts, k_ShaderProperty_InvCameraViewMatrix, invCameraViewMatrix);

            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_MaxBounce, Mathf.Min(Mathf.Max(1, m_settings.MaxBounce), 32));
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_FrameIndex, frameIndex);
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_AccumulatedFrames, frameIndex);
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_EnableAccumulation, m_settings.EnableAccumulation ? 1 : 0);
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_MinRussianRouletteBounce, Mathf.Max(0, m_settings.MinRussianRouletteBounce));
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_MaxNullHit, Mathf.Max(0, m_settings.MaxNullHit));

            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_RayTMin, Mathf.Max(0.0f, m_settings.RayTMin));
            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_RayTMax, Mathf.Max(1.0f, m_settings.RayTMax));
            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_RayOffset, Mathf.Max(0.0f, m_settings.RayOffset));

            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_SkyboxIntensity, m_settings.SkyboxIntensity);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_SkyboxCubemap, GetSkyboxCubemap());

            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_FocusDistance, m_settings.FocusDistance);
            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_ApertureRadius, Mathf.Max(0.0f, m_settings.ApertureRadius));
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_LensMode, Mathf.Max(0, m_settings.LensMode));
            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_AnamorphicSqueeze, Mathf.Max(1e-4f, m_settings.AnamorphicSqueeze));
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_ApertureNumSides, Mathf.Max(3, m_settings.ApertureNumSides));
            cmd.SetRayTracingFloatParam(m_rts, k_ShaderProperty_ApertureAngle, m_settings.ApertureAngle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_ApertureMaskTex, m_settings.ApertureMaskTex != null ? m_settings.ApertureMaskTex : Texture2D.whiteTexture);

            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_rw_OutputRT, m_outputHandle);
            cmd.SetRayTracingAccelerationStructure(m_rts, k_ShaderProperty_RTAccStruct, m_rtas);
            cmd.SetRayTracingShaderPass(m_rts, "SSPTWalker");

            cmd.DispatchRays(m_rts, "SSRTWalkerRayGen", (uint)m_camera.pixelWidth, (uint)m_camera.pixelHeight, 1);
        }

        public override void Postprocess(BakeContext context)
        {
            context.CurrentSPP++;
        }

        public override void Dispose()
        {
            if (m_rtas != null)
            {
                m_rtas.Release();
                m_rtas = null;
            }

            ReleaseRTHandles();
            if (m_fallbackSkyboxCubemap != null)
            {
                UnityEngine.Object.Destroy(m_fallbackSkyboxCubemap);
                m_fallbackSkyboxCubemap = null;
            }
            m_validRenderers = null;
        }
    }
}
