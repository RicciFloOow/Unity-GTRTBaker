using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public struct RTDesc : IEquatable<RTDesc>
    {
        public int Width;
        public int Height;
        /// <summary>
        /// For Tex3D or Tex2DArray
        /// </summary>
        public int VolumeDepth;
        public GraphicsFormat GraphicsFormat;
        public FilterMode FilterMode;
        public TextureWrapMode WrapMode;
        public TextureDimension Dimension;
        public bool EnableRandomWrite;
        public bool UseMipMap;
        //public bool AutoGenerateMips;//我们一般不用自动的, 不如手动的更高效与自由
        public int MipmapLevel;
        public bool IsShadowMap;
        public bool UseStencilBuffer;

        #region ----Properties----
        public GraphicsFormat ColorFormat
        {
            get { return GraphicsFormatUtility.IsDepthStencilFormat(GraphicsFormat) ? GraphicsFormat.None : GraphicsFormat; }
            set { GraphicsFormat = value; }
        }
        public GraphicsFormat DepthFormat
        {
            get { return GraphicsFormatUtility.IsDepthStencilFormat(GraphicsFormat) ? GraphicsFormat : GraphicsFormat.None; }
        }
        public GraphicsFormat StencilFormat
        {
            get { return (UseStencilBuffer && SystemInfo.IsFormatSupported(GraphicsFormat.R8_UInt, GraphicsFormatUsage.StencilSampling)) ? GraphicsFormat.R8_UInt : GraphicsFormat.None; }
        }
        #endregion

        public bool Equals(RTDesc other)
        {
            return (Width == other.Width)
                && (Height == other.Height)
                && (VolumeDepth == other.VolumeDepth)
                && (GraphicsFormat == other.GraphicsFormat)
                && (FilterMode == other.FilterMode)
                && (WrapMode == other.WrapMode)
                && (Dimension == other.Dimension)
                && (EnableRandomWrite == other.EnableRandomWrite)
                && (UseMipMap == other.UseMipMap)
                && (MipmapLevel == other.MipmapLevel)
                && (IsShadowMap == other.IsShadowMap)
                && (UseStencilBuffer == other.UseStencilBuffer);
        }

        #region ----Constructor----
        public RTDesc(RTDesc input)
        {
            this = input;
        }

        public RTDesc(int width, int height, GraphicsFormat graphicsFormat, bool enableRandomReadWrtie = false, int mipmapLevel = 1)
        {
            Width = width;
            Height = height;
            VolumeDepth = 1;
            //
            GraphicsFormat = graphicsFormat;
            FilterMode = FilterMode.Point;
            WrapMode = TextureWrapMode.Clamp;
            Dimension = TextureDimension.Tex2D;
            EnableRandomWrite = enableRandomReadWrtie;
            MipmapLevel = GraphicsUtilities.GetValidMipmapLevel(mipmapLevel, width, height);//TODO:需要检查是否是幂次的
            UseMipMap = MipmapLevel > 1;
            UseStencilBuffer = GraphicsFormatUtility.IsStencilFormat(graphicsFormat);
            IsShadowMap = false;
        }

        //Tex3D or Tex2DArray
        public RTDesc(int width, int height, int volumeDepth, GraphicsFormat graphicsFormat, bool enableRandomReadWrtie = false, int mipmapLevel = 1, bool isTex3D = true)
        {
            Width = width;
            Height = height;
            VolumeDepth = volumeDepth;
            //
            GraphicsFormat = graphicsFormat;
            FilterMode = FilterMode.Point;
            WrapMode = TextureWrapMode.Clamp;
            Dimension = isTex3D ? TextureDimension.Tex3D : TextureDimension.Tex2DArray;
            EnableRandomWrite = enableRandomReadWrtie;
            MipmapLevel = GraphicsUtilities.GetValidMipmapLevel(mipmapLevel, width, height);
            UseMipMap = MipmapLevel > 1;
            UseStencilBuffer = false;//一定不是的
            IsShadowMap = false;
        }

        //Cubemap
        public RTDesc(int size, GraphicsFormat graphicsFormat, bool enableRandomReadWrtie = false, int mipmapLevel = 1)
        {
            int potSize = Mathf.NextPowerOfTwo(size);
            Width = potSize;
            Height = potSize;
            VolumeDepth = 1;
            //
            GraphicsFormat = graphicsFormat;
            FilterMode = FilterMode.Point;
            WrapMode = TextureWrapMode.Clamp;
            Dimension = TextureDimension.Cube;
            EnableRandomWrite = enableRandomReadWrtie;
            MipmapLevel = mipmapLevel;
            UseMipMap = MipmapLevel > 1;
            UseStencilBuffer = false;//一定不是的
            IsShadowMap = false;
        }

        #endregion
    }
}