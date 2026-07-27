using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public class ScreenSpaceRTShadowBaker : BaseBaker
    {
        #region ----Properties----
        private ComputeShader m_cs;
        private RayTracingShader m_rts;

        private int m_InitialAndTemporalKernelIndex;
        private int m_SpatialAndResolveKernelIndex;

        private Matrix4x4 m_prevVPMatrixNoJitter;
        private Matrix4x4 m_prevInvVPMatrix;

        private Camera m_camera;

        private RayTracingAccelerationStructure m_rtas;

        private List<Renderer> m_validRenderers = new List<Renderer>();

        private SSRTShadowLightDataResult m_shadowLightDataResult;

        private bool m_ownsOutputHandle = false;

        private RenderTextureHandle m_camDepthHandle;
        private RenderTextureHandle m_camNormalHandle;
        private RenderTextureHandle m_camMaterialHandle;
        private RenderTextureHandle m_camTopologyIDHandle;
        private RenderTextureHandle m_outputHandle;
        private RenderTargetIdentifier[] m_camGBuffer;

        private RenderTextureHandle m_hisCamDepthHandle;
        private RenderTextureHandle m_hisCamTopologyIDHandle;

        private RenderTextureHandle m_occludedHandle;
        private RenderTextureHandle m_unoccludedHandle;

        private RenderTextureHandle m_RayProposalHandle;
        private RenderTextureHandle m_ResolveWeightHandle;

        private GraphicsBuffer m_GlobalLightTriangles;
        private GraphicsBuffer m_GlobalTriangleAliasTable;

        private GraphicsBuffer m_TemporalReservoirs;
        private GraphicsBuffer m_PingpongReservoirs0;
        private GraphicsBuffer m_PingpongReservoirs1;
        #endregion

        private void SetupRTHandles()
        {
            int width = m_camera.pixelWidth;
            int height = m_camera.pixelHeight;

            m_camDepthHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.D32_SFloat));
            m_camNormalHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat));
            m_camMaterialHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R8G8B8A8_UNorm));
            m_camTopologyIDHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32_SInt));
            m_hisCamDepthHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.D32_SFloat));
            m_hisCamTopologyIDHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32_SInt));
            m_camGBuffer = new RenderTargetIdentifier[]
            {
                m_camNormalHandle,
                m_camMaterialHandle,
                m_camTopologyIDHandle
            };
            if (m_outputHandle == null)
            {
                m_ownsOutputHandle = true;
                m_outputHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));
            }
            m_occludedHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32_SFloat, true));
            m_unoccludedHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32_SFloat, true));
            //
            m_RayProposalHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));
            m_ResolveWeightHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32_SFloat, true));
        }

        private void ReleaseRTHandles()
        {
            m_camGBuffer = null;
            m_camDepthHandle?.Dispose();
            m_camDepthHandle = null;
            m_camNormalHandle?.Dispose();
            m_camNormalHandle = null;
            m_camMaterialHandle?.Dispose();
            m_camMaterialHandle = null;
            m_camTopologyIDHandle?.Dispose();
            m_camTopologyIDHandle = null;
            //
            m_hisCamDepthHandle?.Dispose();
            m_hisCamDepthHandle = null;
            m_hisCamTopologyIDHandle?.Dispose();
            m_hisCamTopologyIDHandle = null;
            //
            m_occludedHandle?.Dispose();
            m_occludedHandle = null;
            m_unoccludedHandle?.Dispose();
            m_unoccludedHandle = null;
            //
            m_RayProposalHandle?.Dispose();
            m_RayProposalHandle = null;
            m_ResolveWeightHandle?.Dispose();
            m_ResolveWeightHandle = null;
        }

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
        private static readonly int k_ShaderProperty_PrevCameraVPMatrixNoJitter = Shader.PropertyToID("_PrevCameraVPMatrixNoJitter");
        private static readonly int k_ShaderProperty_PrevInvCameraVPMatrix = Shader.PropertyToID("_PrevInvCameraVPMatrix"); private static readonly int k_ShaderProperty_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int k_ShaderProperty_ScreenWidth = Shader.PropertyToID("_ScreenWidth");
        private static readonly int k_ShaderProperty_ScreenHeight = Shader.PropertyToID("_ScreenHeight");
        private static readonly int k_ShaderProperty_HistoryTexSize = Shader.PropertyToID("_HistoryTexSize");
        private static readonly int k_ShaderProperty_SpatialNeighborCount = Shader.PropertyToID("_SpatialNeighborCount");
        private static readonly int k_ShaderProperty_SpatialRadius = Shader.PropertyToID("_SpatialRadius");
        private static readonly int k_ShaderProperty_GlobalLightTriangleCount = Shader.PropertyToID("_GlobalLightTriangleCount");
        private static readonly int k_ShaderProperty_CamDepthTexture = Shader.PropertyToID("_CamDepthTexture");
        private static readonly int k_ShaderProperty_CamNormalsTexture = Shader.PropertyToID("_CamNormalsTexture");
        private static readonly int k_ShaderProperty_CamMaterialsTexture = Shader.PropertyToID("_CamMaterialsTexture");
        private static readonly int k_ShaderProperty_CamTopologyIDTexture = Shader.PropertyToID("_CamTopologyIDTexture");
        private static readonly int k_ShaderProperty_HisCamDepthTexture = Shader.PropertyToID("_HisCamDepthTexture");
        private static readonly int k_ShaderProperty_HisCamTopologyIDTexture = Shader.PropertyToID("_HisCamTopologyIDTexture");
        private static readonly int k_ShaderProperty_rw_OutputRT = Shader.PropertyToID("rw_OutputRT");
        private static readonly int k_ShaderProperty_rw_UnoccludedRT = Shader.PropertyToID("rw_UnoccludedRT");
        private static readonly int k_ShaderProperty_rw_OccludedRT = Shader.PropertyToID("rw_OccludedRT");
        private static readonly int k_ShaderProperty_RTAccStruct = Shader.PropertyToID("_RTAccStruct");
        private static readonly int k_ShaderProperty_GlobalTriangles = Shader.PropertyToID("_GlobalLightTriangles");
        private static readonly int k_ShaderProperty_GlobalTriangleAliasTable = Shader.PropertyToID("_GlobalTriangleAliasTable");
        private static readonly int k_ShaderProperty_HistoryReservoirs = Shader.PropertyToID("_HistoryReservoirs");
        private static readonly int k_ShaderProperty_rw_TemporalReservoirs = Shader.PropertyToID("rw_TemporalReservoirs");
        private static readonly int k_ShaderProperty_TemporalReservoirs = Shader.PropertyToID("_TemporalReservoirs");
        private static readonly int k_ShaderProperty_rw_CurrentReservoirs = Shader.PropertyToID("rw_CurrentReservoirs");
        private static readonly int k_ShaderProperty_rw_RayProposalTex = Shader.PropertyToID("rw_RayProposalTex");
        private static readonly int k_ShaderProperty_rw_ResolveWeightTex = Shader.PropertyToID("rw_ResolveWeightTex");
        private static readonly int k_ShaderProperty_RayProposalTex = Shader.PropertyToID("_RayProposalTex");
        private static readonly int k_ShaderProperty_ResolveWeightTex = Shader.PropertyToID("_ResolveWeightTex");
        #endregion

        #region ----Constructor----
        public ScreenSpaceRTShadowBaker(ComputeShader cs, RayTracingShader rts, Camera camera, RenderTextureHandle outputHandle)
        {
            m_cs = cs;
            m_rts = rts;
            m_camera = camera;
            m_outputHandle = outputHandle;
            //
            m_InitialAndTemporalKernelIndex = cs.FindKernel("InitialAndTemporalKernel");
            m_SpatialAndResolveKernelIndex = cs.FindKernel("SpatialAndResolveKernel");
        }
        #endregion

        public override void Preprocess(BakeContext context)
        {
            SetupRTHandles();
            //
            {
                int pixelCount = m_camera.pixelWidth * m_camera.pixelHeight;
                m_TemporalReservoirs = new GraphicsBuffer(GraphicsBuffer.Target.Structured, pixelCount, Marshal.SizeOf<SSRTShadowReservoir>());
                m_PingpongReservoirs0 = new GraphicsBuffer(GraphicsBuffer.Target.Structured, pixelCount, Marshal.SizeOf<SSRTShadowReservoir>());
                m_PingpongReservoirs1 = new GraphicsBuffer(GraphicsBuffer.Target.Structured, pixelCount, Marshal.SizeOf<SSRTShadowReservoir>());
            }
            //
            var processor = new SSRTShadowRenderProcessor();
            m_validRenderers = SceneCollectUtilities.CollectAndProcessRenderers(processor, SceneCollectUtilities.AllowMaterialQueue.Opaque | SceneCollectUtilities.AllowMaterialQueue.AlphaClip);
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
            if (m_validRenderers != null)
            {
                List<SSRTShadowLightMeshInstance> lightMeshInstances = new List<SSRTShadowLightMeshInstance>();
                //不支持alpha clip的光源
                for (int i = 0; i < m_validRenderers.Count; i++)
                {
                    var r = m_validRenderers[i];
                    var mats = r.sharedMaterials;
                    Mesh mesh = null;
                    if (r is MeshRenderer mr)
                    {
                        mesh = r.GetComponent<MeshFilter>().sharedMesh;
                    }
                    else if (r is SkinnedMeshRenderer smr)
                    {
                        mesh = smr.sharedMesh;
                    }
                    //
                    if (mesh == null)
                        continue;
                    //
                    int submeshCount = mesh.subMeshCount;
                    int matCount = mats.Length;
                    float[] submeshEmissions = new float[submeshCount];
                    bool isAlphaClip = false;
                    bool isLight = false;
                    for (int j = 0; j < submeshCount; j++)
                    {
                        if (j < matCount)
                        {
                            var mat = mats[j];
                            if (mat != null)
                            {
                                isAlphaClip |= (mat.GetFloat("_Cutoff") > 0.5f);
                                var emissionColor = mat.GetVector("_EmissionColor");
                                var ei = 0.2126f * emissionColor.x + 0.7152f * emissionColor.y + 0.0722f * emissionColor.z;
                                submeshEmissions[j] = ei;
                                isLight |= (ei > 0.5f);
                            }
                        }
                        else
                        {
                            submeshEmissions[j] = 0;
                        }
                    }
                    if (isAlphaClip)
                        continue;
                    if (!isLight)
                        continue;
                    //
                    SSRTShadowLightMeshInstance lightMeshInstance = new SSRTShadowLightMeshInstance()
                    {
                        mesh = mesh,
                        localToWorld = r.transform.localToWorldMatrix,
                        submeshEmissions = submeshEmissions
                    };
                    lightMeshInstances.Add(lightMeshInstance);
                }
                //
                m_shadowLightDataResult = SSRTShadowLightDataBuilder.Build(lightMeshInstances);
                //
                m_GlobalLightTriangles = new GraphicsBuffer(GraphicsBuffer.Target.Structured, m_shadowLightDataResult.validTriangleCount, Marshal.SizeOf<SSRTShadowGlobalLightTriangle>());
                m_GlobalTriangleAliasTable = new GraphicsBuffer(GraphicsBuffer.Target.Structured, m_shadowLightDataResult.validTriangleCount, Marshal.SizeOf<SSRTShadowAliasEntry>());
                m_GlobalLightTriangles.SetData(m_shadowLightDataResult.triangles, 0, 0, m_shadowLightDataResult.validTriangleCount);
                m_GlobalTriangleAliasTable.SetData(m_shadowLightDataResult.aliasTable, 0, 0, m_shadowLightDataResult.validTriangleCount);
            }
        }

        public override void Setup(BakeContext context, CommandBuffer cmd)
        {

        }
        public override void BuildStepCommand(BakeContext context, CommandBuffer cmd)
        {
            if (m_validRenderers == null)
                return;

            int frameIndex = context.CurrentSPP + 1;

            Matrix4x4 vp = GraphicsUtilities.GetCameraVPZeroMatrix(m_camera, frameIndex);
            Matrix4x4 invVp = vp.inverse;
            Matrix4x4 vpNoJitter = GraphicsUtilities.GetCameraVPZeroMatrix(m_camera, 0);

            if (frameIndex == 1)
            {
                m_prevVPMatrixNoJitter = vpNoJitter;
                m_prevInvVPMatrix = invVp;
            }

            cmd.SetGlobalVector(k_ShaderProperty_CameraPos, m_camera.transform.position);
            cmd.SetGlobalMatrix(k_ShaderProperty_CameraVPMatrix, vp);
            cmd.SetGlobalMatrix(k_ShaderProperty_InvCameraVPMatrix, invVp);
            cmd.SetGlobalMatrix(k_ShaderProperty_PrevCameraVPMatrixNoJitter, m_prevVPMatrixNoJitter);
            cmd.SetGlobalMatrix(k_ShaderProperty_PrevInvCameraVPMatrix, m_prevInvVPMatrix);

            cmd.SetRenderTarget(m_camGBuffer, m_camDepthHandle);
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
            //

            int threadGroupsX = Mathf.CeilToInt(m_camera.pixelWidth / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(m_camera.pixelHeight / 8.0f);

            bool isEvenFrame = (frameIndex % 2 == 0);
            var historyReservoirs = isEvenFrame ? m_PingpongReservoirs1 : m_PingpongReservoirs0;
            var currentReservoirs = isEvenFrame ? m_PingpongReservoirs0 : m_PingpongReservoirs1;

            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_FrameIndex, frameIndex);
            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_ScreenWidth, m_camera.pixelWidth);
            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_ScreenHeight, m_camera.pixelHeight);
            cmd.SetComputeVectorParam(m_cs, k_ShaderProperty_HistoryTexSize, new Vector4(m_camera.pixelWidth, m_camera.pixelHeight, 1.0f / m_camera.pixelWidth, 1.0f / m_camera.pixelHeight));
            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_GlobalLightTriangleCount, m_shadowLightDataResult.validTriangleCount);

            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_CamDepthTexture, m_camDepthHandle);
            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_CamNormalsTexture, m_camNormalHandle);
            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_CamMaterialsTexture, m_camMaterialHandle);
            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_CamTopologyIDTexture, m_camTopologyIDHandle);
            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_HisCamDepthTexture, m_hisCamDepthHandle);
            cmd.SetComputeTextureParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_HisCamTopologyIDTexture, m_hisCamTopologyIDHandle);

            cmd.SetComputeBufferParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_GlobalTriangles, m_GlobalLightTriangles);
            cmd.SetComputeBufferParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_GlobalTriangleAliasTable, m_GlobalTriangleAliasTable);
            cmd.SetComputeBufferParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_HistoryReservoirs, historyReservoirs);
            cmd.SetComputeBufferParam(m_cs, m_InitialAndTemporalKernelIndex, k_ShaderProperty_rw_TemporalReservoirs, m_TemporalReservoirs);

            cmd.DispatchCompute(m_cs, m_InitialAndTemporalKernelIndex, threadGroupsX, threadGroupsY, 1);

            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_SpatialNeighborCount, 5);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_SpatialRadius, 30.0f);

            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_CamDepthTexture, m_camDepthHandle);
            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_CamNormalsTexture, m_camNormalHandle);
            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_CamMaterialsTexture, m_camMaterialHandle);
            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_CamTopologyIDTexture, m_camTopologyIDHandle);

            cmd.SetComputeBufferParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_GlobalTriangles, m_GlobalLightTriangles);
            cmd.SetComputeBufferParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_TemporalReservoirs, m_TemporalReservoirs);
            cmd.SetComputeBufferParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_rw_CurrentReservoirs, currentReservoirs);

            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_rw_RayProposalTex, m_RayProposalHandle);
            cmd.SetComputeTextureParam(m_cs, m_SpatialAndResolveKernelIndex, k_ShaderProperty_rw_ResolveWeightTex, m_ResolveWeightHandle);

            cmd.DispatchCompute(m_cs, m_SpatialAndResolveKernelIndex, threadGroupsX, threadGroupsY, 1);

            //
            cmd.SetRayTracingIntParam(m_rts, k_ShaderProperty_FrameIndex, frameIndex);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_RayProposalTex, m_RayProposalHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_ResolveWeightTex, m_ResolveWeightHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_CamDepthTexture, m_camDepthHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_CamNormalsTexture, m_camNormalHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_CamMaterialsTexture, m_camMaterialHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_rw_OutputRT, m_outputHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_rw_OccludedRT, m_occludedHandle);
            cmd.SetRayTracingTextureParam(m_rts, k_ShaderProperty_rw_UnoccludedRT, m_unoccludedHandle);
            cmd.SetRayTracingAccelerationStructure(m_rts, k_ShaderProperty_RTAccStruct, m_rtas);
            cmd.SetRayTracingShaderPass(m_rts, "SSRTShadow");

            cmd.DispatchRays(m_rts, "SSRTShadowRayGen", (uint)m_camera.pixelWidth, (uint)m_camera.pixelHeight, 1);

            cmd.CopyTexture(m_camDepthHandle, m_hisCamDepthHandle);
            cmd.CopyTexture(m_camTopologyIDHandle, m_hisCamTopologyIDHandle);

            m_prevVPMatrixNoJitter = vpNoJitter;
            m_prevInvVPMatrix = invVp;
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
            if (m_ownsOutputHandle)
            {
                m_outputHandle?.Dispose();
            }
            m_outputHandle = null;
            m_shadowLightDataResult?.Dispose();
            //
            m_GlobalLightTriangles?.Release();
            m_GlobalLightTriangles = null;
            m_GlobalTriangleAliasTable?.Release();
            m_GlobalTriangleAliasTable = null;
            m_TemporalReservoirs?.Release();
            m_TemporalReservoirs = null;
            m_PingpongReservoirs0?.Release();
            m_PingpongReservoirs0 = null;
            m_PingpongReservoirs1?.Release();
            m_PingpongReservoirs1 = null;
        }
    }
}