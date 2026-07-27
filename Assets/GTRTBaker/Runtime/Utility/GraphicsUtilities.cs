using System.Runtime.CompilerServices;
using UnityEngine;


namespace GTRTBaker
{
    public static class GraphicsUtilities
    {
        #region ----Sobol Sequence----
        private static uint ReverseBits(uint bits)
        {
            bits = (bits << 16) | (bits >> 16);
            bits = ((bits & 0x00ff00ff) << 8) | ((bits & 0xff00ff00) >> 8);
            bits = ((bits & 0x0f0f0f0f) << 4) | ((bits & 0xf0f0f0f0) >> 4);
            bits = ((bits & 0x33333333) << 2) | ((bits & 0xcccccccc) >> 2);
            bits = ((bits & 0x55555555) << 1) | ((bits & 0xaaaaaaaa) >> 1);
            return bits;
        }

        public static Vector2 GetQuasirandomJitter(uint index)
        {
            const float a1 = 0.8566748838545029f;
            const float a2 = 0.7338918566271260f;

            float x = (a1 * index) % 1.0f;
            float y = (a2 * index) % 1.0f;

            return new Vector2(x, y);
        }
        #endregion

        #region ----Camera----
        public static Matrix4x4 GetCameraVPZeroMatrix(Camera camera, int frameCount = 0)
        {
            Matrix4x4 proj = camera.projectionMatrix;
            if (frameCount != 0)
            {
                var jitter = GetQuasirandomJitter((uint)frameCount);

                float jitterX = jitter.x - 0.5f;
                float jitterY = jitter.y - 0.5f;

                float offsetX = jitterX * 2.0f / camera.pixelWidth;
                float offsetY = jitterY * 2.0f / camera.pixelHeight;

                if (camera.orthographic)
                {
                    proj.m03 += offsetX;
                    proj.m13 += offsetY;
                }
                else
                {
                    proj.m02 += offsetX;
                    proj.m12 += offsetY;
                }
            }
            proj = GL.GetGPUProjectionMatrix(proj, true);
            Matrix4x4 view = camera.transform.worldToLocalMatrix;
            view.SetColumn(3, new Vector4(0, 0, 0, 1f));
            view = Matrix4x4.Scale(new Vector3(1, 1, -1)) * view;
            return proj * view;
        }
        #endregion

        public static int GetValidMipmapLevel(int mipmap, int width, int height)
        {
            if (IsPowerOfTwo(width) && IsPowerOfTwo(height))
            {
                return mipmap;
            }
            return 1;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static bool IsPowerOfTwo(int n)
        {
            return (n > 0) && ((n & (n - 1)) == 0);
        }
    }
}