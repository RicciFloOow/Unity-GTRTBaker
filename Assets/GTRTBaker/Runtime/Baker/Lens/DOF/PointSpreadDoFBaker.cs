using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public class PointSpreadDoFBaker : BaseBaker
    {
        #region ----Properties----
        private ComputeShader m_cs;
        private Camera m_camera;
        private int m_kernelId;

        private RayTracingAccelerationStructure m_rtas;

        private float m_focusDistance;
        private float m_targetDistance;
        private float m_apertureRadius;
        private int m_lensMode;
        private float m_anamorphicSqueeze;
        private int m_apertureNumSides;
        private float m_apertureAngle;
        private Color m_surfaceColor;
        private Texture m_apertureMaskTex;
        private Mesh m_targetMesh;

        private bool m_ownsOutputNoDoFHandle = false;
        private bool m_ownsOutputDoFHandle = false;

        private RenderTextureHandle m_outputNoDoFHandle;
        private RenderTextureHandle m_outputDoFHandle;
        #endregion

        #region ----Constructor----
        public PointSpreadDoFBaker(
            ComputeShader cs,
            Camera camera,
            RenderTextureHandle outputNoDoF,
            RenderTextureHandle outputDoF,
            Color surfaceColor,
            float focusDistance = 10.0f,
            float apertureRadius = 0.05f,
            int lensMode = 0,
            float anamorphicSqueeze = 1.0f,
            int apertureNumSides = 5,
            float apertureAngle = 0.0f,
            Texture apertureMaskTex = null,
            Mesh targetMesh = null,
            float targetDistance = 10)
        {
            m_cs = cs;
            m_camera = camera;
            m_outputNoDoFHandle = outputNoDoF;
            m_outputDoFHandle = outputDoF;

            m_focusDistance = focusDistance;
            m_apertureRadius = apertureRadius;
            m_lensMode = lensMode;
            m_anamorphicSqueeze = anamorphicSqueeze;
            m_apertureNumSides = apertureNumSides;
            m_apertureAngle = apertureAngle;
            m_surfaceColor = surfaceColor;
            m_apertureMaskTex = apertureMaskTex;
            m_targetMesh = targetMesh;
            m_targetDistance = targetDistance;

            if (m_cs != null)
                m_kernelId = m_cs.FindKernel("GTPointSpreadDoFKernel");
        }
        #endregion

        #region ----Render Processor----
        internal class PSDoFRenderProcessor : ISceneBakerRendererProcessor
        {
            public void Process(Renderer renderer)
            {
                //什么都不用做, 直接清空
            }
        }
        #endregion

        #region ----Constants----
        private static readonly RayTracingSubMeshFlags[] k_rtSubMeshFlags = new RayTracingSubMeshFlags[]
        {
            RayTracingSubMeshFlags.Enabled
        };

        private static readonly int k_ShaderProperty_CameraProjMatrix = Shader.PropertyToID("_CameraProjMatrix");
        private static readonly int k_ShaderProperty_InvCameraViewMatrix = Shader.PropertyToID("_InvCameraViewMatrix");
        private static readonly int k_ShaderProperty_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int k_ShaderProperty_FocusDistance = Shader.PropertyToID("_FocusDistance");
        private static readonly int k_ShaderProperty_ApertureRadius = Shader.PropertyToID("_ApertureRadius");
        private static readonly int k_ShaderProperty_SurfaceColor = Shader.PropertyToID("_SurfaceColor");
        private static readonly int k_ShaderProperty_LensMode = Shader.PropertyToID("_LensMode");
        private static readonly int k_ShaderProperty_AnamorphicSqueeze = Shader.PropertyToID("_AnamorphicSqueeze");
        private static readonly int k_ShaderProperty_ApertureNumSides = Shader.PropertyToID("_ApertureNumSides");
        private static readonly int k_ShaderProperty_ApertureAngle = Shader.PropertyToID("_ApertureAngle");
        private static readonly int k_ShaderProperty_ApertureMaskTex = Shader.PropertyToID("_ApertureMaskTex");
        private static readonly int k_ShaderProperty_RTAccStruct = Shader.PropertyToID("_RTAccStruct");
        private static readonly int k_ShaderProperty_rw_OutputNoDoF = Shader.PropertyToID("rw_OutputNoDoF");
        private static readonly int k_ShaderProperty_rw_OutputDoF = Shader.PropertyToID("rw_OutputDoF");
        #endregion

        private void SetupRTHandles()
        {
            int width = m_camera.pixelWidth;
            int height = m_camera.pixelHeight;

            if (m_outputNoDoFHandle == null)
            {
                m_ownsOutputNoDoFHandle = true;
                m_outputNoDoFHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));
            }

            if (m_outputDoFHandle == null)
            {
                m_ownsOutputDoFHandle = true;
                m_outputDoFHandle = new RenderTextureHandle(new RTDesc(width, height, GraphicsFormat.R32G32B32A32_SFloat, true));
            }
        }

        public override void Setup(BakeContext context, CommandBuffer cmd)
        {

        }

        public override void Preprocess(BakeContext context)
        {
            SetupRTHandles();

            var processor = new PSDoFRenderProcessor();
            var validRenderers = SceneCollectUtilities.CollectAndProcessRenderers(processor);
            //不考虑场景中本身的renderer
            foreach (var renderer in validRenderers)
            {
                renderer.gameObject.SetActive(false);
            }

            var rtasSettings = new RayTracingAccelerationStructure.Settings
            {
                managementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
                rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything,
                layerMask = -1
            };

            m_rtas = new RayTracingAccelerationStructure(rtasSettings);

            {
                GameObject go = new GameObject()
                {
                    name = "PointSpreadTarget"
                };
                var mr = go.AddComponent<MeshRenderer>();
                go.transform.position = m_camera.transform.position + m_camera.transform.forward * m_targetDistance;
                go.transform.rotation = m_camera.transform.rotation;
                go.transform.localScale = Vector3.one;
                mr.forceRenderingOff = true;
                mr.sharedMaterial = new Material(Shader.Find("GTRTBaker/Common/RTGbuffer"));
                //
                var mf = go.AddComponent<MeshFilter>();
                if (m_targetMesh != null)
                {
                    mf.sharedMesh = m_targetMesh;
                }
                else
                {
                    //空的则是"点"网格
                    var m = new Mesh()
                    {
                        name = "PointSpreadMesh"
                    };
                    int width = m_camera.pixelWidth;
                    int height = m_camera.pixelHeight;
                    {
                        float pixelWorldSize = 0f;

                        if (m_camera.orthographic)
                        {
                            float frustumHeight = m_camera.orthographicSize * 2f;
                            pixelWorldSize = frustumHeight / height;
                        }
                        else
                        {
                            float halfFovRad = (m_camera.fieldOfView * 0.5f) * Mathf.Deg2Rad;
                            float frustumHeight = 2f * m_targetDistance * Mathf.Tan(halfFovRad);
                            pixelWorldSize = frustumHeight / height;
                        }
                        
                        float halfSize = pixelWorldSize * 0.5f;

                        Vector3[] vertices = new Vector3[4]
                        {
                            new Vector3(-halfSize, -halfSize, 0),
                            new Vector3(halfSize, -halfSize, 0),
                            new Vector3(-halfSize, halfSize, 0),
                            new Vector3(halfSize, halfSize, 0)
                        };
                        int[] triangles = new int[6] { 0, 2, 1, 2, 3, 1 };
                        m.vertices = vertices;
                        m.triangles = triangles;
                    }
                    //
                    mf.sharedMesh = m;
                }
                //
                m_rtas.AddInstance(mr, k_rtSubMeshFlags);
            }

            m_rtas.Build(m_camera.transform.position);
        }

        public override void BuildStepCommand(BakeContext context, CommandBuffer cmd)
        {
            int frameIndex = context.CurrentSPP + 1;

            Matrix4x4 proj = m_camera.projectionMatrix;
            proj = GL.GetGPUProjectionMatrix(proj, true);
            Matrix4x4 view = m_camera.transform.worldToLocalMatrix;
            view.SetColumn(3, new Vector4(0, 0, 0, 1f));
            Matrix4x4 invView = view.inverse;

            cmd.SetComputeMatrixParam(m_cs, k_ShaderProperty_CameraProjMatrix, proj);
            cmd.SetComputeMatrixParam(m_cs, k_ShaderProperty_InvCameraViewMatrix, invView);

            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_FrameIndex, frameIndex);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_FocusDistance, m_focusDistance);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_ApertureRadius, m_apertureRadius);
            cmd.SetComputeVectorParam(m_cs, k_ShaderProperty_SurfaceColor, m_surfaceColor);
            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_LensMode, m_lensMode);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_AnamorphicSqueeze, m_anamorphicSqueeze);
            cmd.SetComputeIntParam(m_cs, k_ShaderProperty_ApertureNumSides, m_apertureNumSides);
            cmd.SetComputeFloatParam(m_cs, k_ShaderProperty_ApertureAngle, m_apertureAngle);

            if (m_apertureMaskTex != null)
            {
                cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_ApertureMaskTex, m_apertureMaskTex);
            }
            else
            {
                cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_ApertureMaskTex, Texture2D.whiteTexture);
            }

            cmd.SetRayTracingAccelerationStructure(m_cs, m_kernelId, k_ShaderProperty_RTAccStruct, m_rtas);
            cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_rw_OutputNoDoF, m_outputNoDoFHandle);
            cmd.SetComputeTextureParam(m_cs, m_kernelId, k_ShaderProperty_rw_OutputDoF, m_outputDoFHandle);

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

            if (m_ownsOutputNoDoFHandle) 
                m_outputNoDoFHandle?.Dispose();
            m_outputNoDoFHandle = null;

            if (m_ownsOutputDoFHandle) 
                m_outputDoFHandle?.Dispose();
            m_outputDoFHandle = null;
        }
    }
}