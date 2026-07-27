using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

namespace GTRTBaker
{
    public class ScreenSpaceRTAOBaker : BaseBaker
    {
        #region ----Properties----
        private ComputeShader m_cs;

        private Camera m_camera;

        private int m_kernelId;

        private readonly float m_aoRadius;

        private RayTracingAccelerationStructure m_rtas;

        private List<Renderer> m_validRenderers = new List<Renderer>();

        private bool m_ownsCamDepthHandle = false;
        private bool m_ownsCamNormalHandle = false;
        private bool m_ownsOutputHandle = false;

        private RenderTextureHandle m_camDepthHandle;
        private RenderTextureHandle m_camNormalHandle;
        private RenderTextureHandle m_outputHandle;
        #endregion

        private void SetupRTHandles()
        {
            int width = m_camera.pixelWidth;
            int height = m_camera.pixelHeight;

            if (m_camDepthHandle == null)
            {
                m_ownsCamDepthHandle = true;
                m_camDepthHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.D32_SFloat));
            }
            if (m_camNormalHandle == null)
            {
                m_ownsCamNormalHandle = true;
                m_camNormalHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat));
            }
            if (m_outputHandle == null)
            {
                m_ownsOutputHandle = true;
                m_outputHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));
            }
        }

        private void ReleaseRTHandles()
        {
            if (m_ownsCamDepthHandle)
                m_camDepthHandle?.Dispose();
            m_camDepthHandle = null;
            if (m_ownsCamNormalHandle)
                m_camNormalHandle?.Dispose();
            m_camNormalHandle = null;
            if (m_ownsOutputHandle)
                m_outputHandle?.Dispose();
            m_outputHandle = null;
        }

        #region ----Constructor----
        public ScreenSpaceRTAOBaker(ComputeShader cs, Camera camera, RenderTextureHandle outputHandle, float aoRadius = 0.5f, RenderTextureHandle camDepth = null, RenderTextureHandle camNormal = null)
        {
            m_cs = cs;
            m_camera = camera;
            m_camDepthHandle = camDepth;
            m_camNormalHandle = camNormal;
            m_outputHandle = outputHandle;
            m_aoRadius = aoRadius;

            if (m_cs != null)
                m_kernelId = m_cs.FindKernel("SSRTAOKernel");
        }
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
        private static readonly int k_ShaderProperty_CameraVPMatrix = Shader.PropertyToID("_CameraVPMatrix");
        private static readonly int k_ShaderProperty_InvCameraVPMatrix = Shader.PropertyToID("_InvCameraVPMatrix");
        private static readonly int k_ShaderProperty_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int k_ShaderProperty_AORadius = Shader.PropertyToID("_AORadius");
        private static readonly int k_ShaderProperty_CamDepthTexture = Shader.PropertyToID("_CamDepthTexture");
        private static readonly int k_ShaderProperty_CamNormalsTexture = Shader.PropertyToID("_CamNormalsTexture");
        private static readonly int k_ShaderProperty_rw_OutputRT = Shader.PropertyToID("rw_OutputRT");
        private static readonly int k_ShaderProperty_RTAccStruct = Shader.PropertyToID("_RTAccStruct");
        #endregion

        public override void Preprocess(BakeContext context)
        {
            SetupRTHandles();
            var processor = new RTGBufferRenderProcessor();
            m_validRenderers = SceneCollectUtilities.CollectAndProcessRenderers(processor);
            //
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
                    var r = m_validRenderers[i];
                    m_rtas.AddInstance(r, k_rtSubMeshFlags);
                }
            }
            m_rtas.Build(m_camera.transform.position);
            //
        }

        public override void Setup(BakeContext context, CommandBuffer cmd)
        {

        }

        public override void BuildStepCommand(BakeContext context, CommandBuffer cmd)
        {
            int frameIndex = context.CurrentSPP + 1;

            Matrix4x4 vp = GraphicsUtilities.GetCameraVPZeroMatrix(m_camera, frameIndex);
            Matrix4x4 invVp = vp.inverse;

            cmd.SetGlobalVector(k_ShaderProperty_CameraPos, m_camera.transform.position);
            cmd.SetGlobalMatrix(k_ShaderProperty_CameraVPMatrix, vp);
            cmd.SetGlobalMatrix(k_ShaderProperty_InvCameraVPMatrix, invVp);

            cmd.EnableShaderKeyword("GTRT_BAKE_NORMAL");
            cmd.DisableShaderKeyword("GTRT_BAKE_FULL");

            cmd.SetRenderTarget(m_camNormalHandle, m_camDepthHandle);
            cmd.ClearRenderTarget(true, true, Color.clear);

            foreach (var renderer in m_validRenderers)
            {
                if (renderer != null)
                {
                    var mats = renderer.sharedMaterials;
                    for (int i = 0; i < mats.Length; i++)
                    {
                        cmd.DrawRenderer(renderer, mats[i], i);
                    }
                }
            }

            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_FrameIndex, frameIndex);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_AORadius, m_aoRadius);

            cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_CamDepthTexture, m_camDepthHandle);
            cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_CamNormalsTexture, m_camNormalHandle);
            cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_rw_OutputRT, m_outputHandle);
            cmd.SetRayTracingAccelerationStructure(m_cs, m_kernelId, k_ShaderProperty_RTAccStruct, m_rtas);

            int threadGroupsX = Mathf.CeilToInt(m_camera.pixelWidth / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(m_camera.pixelHeight / 4.0f);
            cmd.DispatchCompute(m_cs, m_kernelId, threadGroupsX, threadGroupsY, 1);
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
        }
    }
}