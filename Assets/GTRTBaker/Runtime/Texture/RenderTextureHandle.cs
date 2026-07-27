using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public class RenderTextureHandle : IDisposable
    {
        internal RenderTexture m_RT;
        internal RenderTargetIdentifier[] m_RTIdentifiers;
        /// <summary>
        /// x: mipmap, y: cubemap, z: volumeDepth
        /// </summary>
        internal Vector3Int m_TexSubresourcesDim;

        public int LastUsedFrame { get; internal set; }

        #region ----Properties----
        public TextureDimension RTDimension => m_RT.dimension;

        public int Width => m_RT.width;

        public int Height => m_RT.height;

        public int VolumeDepth => m_RT.volumeDepth;

        public GraphicsFormat GraphicsFormat => m_RT.graphicsFormat;
        #endregion

        #region ----Constructor----
        public RenderTextureHandle(RTDesc desc)
        {
            //RTDesc里的数据都是准确的(mipmap是否真的能启用都是已经确定的了), 我们可以直接用
            m_RT = new RenderTexture(desc.Width, desc.Height, desc.ColorFormat, desc.DepthFormat, desc.MipmapLevel)
            {
                filterMode = desc.FilterMode,
                useMipMap = desc.MipmapLevel > 1,
                autoGenerateMips = false,//一定不用自动的
                enableRandomWrite = desc.EnableRandomWrite,
                volumeDepth = desc.VolumeDepth,
                dimension = desc.Dimension,
                wrapMode = desc.WrapMode,
                useDynamicScale = false
            };
            m_RT.Create();
            //
            {
                int mipmapLevelDim = desc.MipmapLevel;
                int cubemapDim = 1;
                int texDepthDim = 1;
                //
                switch (desc.Dimension)
                {
                    case TextureDimension.Tex3D:
                    case TextureDimension.Tex2DArray:
                        cubemapDim = 1;
                        texDepthDim = desc.VolumeDepth;
                        break;
                    case TextureDimension.Cube:
                        cubemapDim = 6;
                        texDepthDim = 1;
                        break;
                    case TextureDimension.CubeArray:
                        //虽然可以支持, 但是我们基本不会去用
                        cubemapDim = 6;
                        texDepthDim = desc.VolumeDepth;
                        break;
                }
                //
                m_TexSubresourcesDim = new Vector3Int(mipmapLevelDim, cubemapDim, texDepthDim);
            }
            //
            m_RTIdentifiers = new RenderTargetIdentifier[m_TexSubresourcesDim.x * m_TexSubresourcesDim.y * m_TexSubresourcesDim.z];
            //
            for (int i = 0; i < m_TexSubresourcesDim.x; i++)
            {
                for (int j = 0; j < m_TexSubresourcesDim.y; j++)
                {
                    CubemapFace face = m_TexSubresourcesDim.y == 1 ? CubemapFace.Unknown : (CubemapFace)j;
                    for (int k = 0; k < m_TexSubresourcesDim.z; k++)
                    {
                        int index = i + j * m_TexSubresourcesDim.x + k * m_TexSubresourcesDim.x * m_TexSubresourcesDim.y;
                        m_RTIdentifiers[index] = new RenderTargetIdentifier(m_RT, i, face, k);
                    }
                }
            }
        }
        #endregion

        #region ----Implicit Conversion Operator----
        public static implicit operator RenderTexture(RenderTextureHandle handle)
        {
            if (handle.m_RT == null)
                return null;
            return handle.m_RT;
        }

        public static implicit operator RenderTargetIdentifier(RenderTextureHandle handle)
        {
            if (handle.m_RTIdentifiers == null)
                return default;
            return handle.m_RTIdentifiers[0];
        }
        #endregion

        public RenderTargetIdentifier GetRenderTargetIdentifier(int mip, CubemapFace face = CubemapFace.Unknown, int volumeDepth = 0)
        {
            if (m_RTIdentifiers == null)
                return default;
            if ((mip < m_TexSubresourcesDim.x) && (volumeDepth < m_TexSubresourcesDim.z))
            {
                int faceIndex = Mathf.Max(0, (int)face);
                return m_RTIdentifiers[mip + faceIndex * m_TexSubresourcesDim.x + volumeDepth * m_TexSubresourcesDim.x * m_TexSubresourcesDim.y];
            }
            else
            {
                return m_RTIdentifiers[0];
            }
        }

        public void SetName(string name)
        {
            m_RT.name = name;
        }

        public void Dispose()
        {
            if (m_RT != null)
            {
                m_RT.Release();
#if UNITY_EDITOR
                if (!Application.isPlaying)
                {
                    UnityEngine.Object.DestroyImmediate(m_RT);
                }
                else
                {
#endif
                    UnityEngine.Object.Destroy(m_RT);
#if UNITY_EDITOR
                }
#endif
                m_RT = null;
            }
            m_RTIdentifiers = null;
        }
    }
}