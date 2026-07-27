using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    [Serializable]
    public struct ReferencePTSettings
    {
        public int MaxBounces;
        public float SkyIntensity;
        public float ExposureAdjustment;
        public bool EnableAntiAliasing;
        public bool EnableAccumulation;
        public float FocusDistance;
        public float ApertureSize;

        public static ReferencePTSettings Default => new ReferencePTSettings
        {
            MaxBounces = 4,
            SkyIntensity = 1.0f,
            ExposureAdjustment = 1.0f,
            EnableAntiAliasing = true,
            EnableAccumulation = true,
            FocusDistance = 10.0f,
            ApertureSize = 0.0f
        };
    }

    public class ReferencePTBaker : BaseBaker
    {
        public RenderTextureHandle OutputHandle => m_accumulationHandle;

        #region ----Properties----
        private RayTracingShader m_rts;
        private Camera m_camera;
        private ReferencePTSettings m_settings;


        private RayTracingAccelerationStructure m_rtas;
        private List<Renderer> m_validRenderers;

        private RenderTextureHandle m_accumulationHandle;

        private ComputeBuffer m_lightDatasBuffer;
        private ComputeBuffer m_flattenedLightIndicesBuffer;
        private ComputeBuffer m_chunkOffsetsBuffer;

        private Bounds m_sceneBounds;
        private Vector3 m_chunkSize;
        #endregion

        #region ----Constant----
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

        private static readonly Vector3Int k_subdivisions = new Vector3Int(4, 4, 4);
        #endregion

        #region ----Constructor----
        public ReferencePTBaker(RayTracingShader rts, Camera camera, ReferencePTSettings settings)
        {
            m_rts = rts;
            m_camera = camera;
            m_settings = settings;
        }
        #endregion

        public override void Preprocess(BakeContext context)
        {
            int width = m_camera.pixelWidth;
            int height = m_camera.pixelHeight;

            m_accumulationHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));

            var processor = new ReferencePTRenderProcessor();
            m_validRenderers = SceneCollectUtilities.CollectAndProcessRenderers(processor);

            var rtasSettings = new RayTracingAccelerationStructure.Settings
            {
                managementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
                rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything,
                layerMask = -1
            };
            m_rtas = new RayTracingAccelerationStructure(rtasSettings);

            if (m_validRenderers != null && m_validRenderers.Count > 0)
            {
                m_sceneBounds = m_validRenderers[0].bounds;

                for (int i = 0; i < m_validRenderers.Count; i++)
                {
                    var r = m_validRenderers[i];
                    m_rtas.AddInstance(r, k_rtSubMeshFlags);
                    m_sceneBounds.Encapsulate(r.bounds);
                }
            }
            else
            {
                m_sceneBounds = new Bounds(Vector3.zero, Vector3.zero);
            }

            m_chunkSize = new Vector3(
                m_sceneBounds.size.x / k_subdivisions.x,
                m_sceneBounds.size.y / k_subdivisions.y,
                m_sceneBounds.size.z / k_subdivisions.z);

            m_rtas.Build(m_camera.transform.position);
            //

            List<int> flattenedIndices;
            List<Vector2Int> chunkOffsets;
            var lightDatas = SceneCollectUtilities.AnalyzeLightDatasWithChunks<ReferencePTLightData>(m_sceneBounds, k_subdivisions, new ReferencePTLightFilter(), new ReferencePTLightDataConverter(), out flattenedIndices, out chunkOffsets);

            CreateComputeBuffer(ref m_lightDatasBuffer, lightDatas, Marshal.SizeOf<ReferencePTLightData>());
            CreateComputeBuffer(ref m_flattenedLightIndicesBuffer, flattenedIndices, sizeof(int));
            CreateComputeBuffer(ref m_chunkOffsetsBuffer, chunkOffsets, Marshal.SizeOf<Vector2Int>());
        }

        public override void Setup(BakeContext context, CommandBuffer cmd)
        {

        }
        public override void BuildStepCommand(BakeContext context, CommandBuffer cmd)
        {
            int frameIndex = context.CurrentSPP + 1;

            Matrix4x4 viewMatrix = m_camera.transform.worldToLocalMatrix;
            viewMatrix.SetColumn(3, new Vector4(0, 0, 0, 1f));
            cmd.SetRayTracingMatrixParam(m_rts, "_CameraViewMatrix", viewMatrix);
            cmd.SetRayTracingMatrixParam(m_rts, "_InvCameraViewMatrix", viewMatrix.inverse);
            cmd.SetRayTracingMatrixParam(m_rts, "_CameraProjMatrix", GL.GetGPUProjectionMatrix(m_camera.projectionMatrix, true));

            cmd.SetRayTracingIntParam(m_rts, "_FrameNumber", frameIndex);
            cmd.SetRayTracingIntParam(m_rts, "_MaxBounces", m_settings.MaxBounces);
            cmd.SetRayTracingFloatParam(m_rts, "_SkyIntensity", m_settings.SkyIntensity);
            cmd.SetRayTracingFloatParam(m_rts, "_ExposureAdjustment", m_settings.ExposureAdjustment);
            cmd.SetRayTracingIntParam(m_rts, "_AccumulatedFrames", frameIndex);
            cmd.SetRayTracingIntParam(m_rts, "_EnableAntiAliasing", m_settings.EnableAntiAliasing ? 1 : 0);
            cmd.SetRayTracingIntParam(m_rts, "_EnableAccumulation", m_settings.EnableAccumulation ? 1 : 0);
            cmd.SetRayTracingFloatParam(m_rts, "_FocusDistance", m_settings.FocusDistance);
            cmd.SetRayTracingFloatParam(m_rts, "_ApertureSize", m_settings.ApertureSize);

            var camPos = m_camera.transform.position;
            cmd.SetRayTracingVectorParam(m_rts, "_SceneBoundsMin", m_sceneBounds.min - camPos);//相对相机位置
            cmd.SetRayTracingVectorParam(m_rts, "_CameraPos", camPos);
            cmd.SetRayTracingVectorParam(m_rts, "_LightChunkSize", m_chunkSize);
            cmd.SetRayTracingVectorParam(m_rts, "_Subdivisions", new Vector3(k_subdivisions.x, k_subdivisions.y, k_subdivisions.z));

            cmd.SetRayTracingTextureParam(m_rts, "rw_accumulationBuffer", m_accumulationHandle);
            cmd.SetRayTracingAccelerationStructure(m_rts, "_SceneBVH", m_rtas);

            cmd.SetRayTracingBufferParam(m_rts, "_LightDatasBuffer", m_lightDatasBuffer);
            cmd.SetRayTracingBufferParam(m_rts, "_FlattenedLightIndicesBuffer", m_flattenedLightIndicesBuffer);
            cmd.SetRayTracingBufferParam(m_rts, "_ChunkOffsetsBuffer", m_chunkOffsetsBuffer);

            cmd.SetRayTracingShaderPass(m_rts, "referencePT");
            cmd.DispatchRays(m_rts, "RayGen", (uint)m_camera.pixelWidth, (uint)m_camera.pixelHeight, 1);
        }

        public override void Postprocess(BakeContext context)
        {
            context.CurrentSPP++;
        }

        public override void Dispose()
        {
            m_rtas?.Release();
            m_rtas = null;

            m_accumulationHandle?.Dispose();
            m_accumulationHandle = null;

            m_lightDatasBuffer?.Release();
            m_flattenedLightIndicesBuffer?.Release();
            m_chunkOffsetsBuffer?.Release();
        }

        private void CreateComputeBuffer<T>(ref ComputeBuffer buffer, List<T> data, int stride) where T : struct
        {
            if (data == null || data.Count == 0)
            {
                buffer = new ComputeBuffer(1, stride);
                buffer.SetData(new T[] { default(T) });
            }
            else
            {
                buffer = new ComputeBuffer(data.Count, stride);
                buffer.SetData(data);
            }
        }
    }
}