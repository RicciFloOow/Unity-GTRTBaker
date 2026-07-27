using UnityEngine;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public class SSRTShadowRenderProcessor : ISceneBakerRendererProcessor
    {
        public SSRTShadowRenderProcessor(bool enableAlphaClip = true)
        {
            EnableAlphaClip = enableAlphaClip;
        }

        public bool EnableAlphaClip { get; set; }

        private static Shader s_targetShader;
        private static Shader TargetShader
        {
            get
            {
                if (s_targetShader == null)
                    s_targetShader = Shader.Find("GTRTBaker/Shadow/SSRTShadowAlphaClip");
                return s_targetShader;
            }
        }

        private Material BindSSRTShadowMat(Material src, int objID)
        {
            if (src == null) return new Material(TargetShader);

            if (src.shader == TargetShader)
            {
                return src;
            }

            Material dst = new Material(TargetShader);

            if (src.HasProperty("_MainTex"))
            {
                dst.SetTexture("_MainTex", src.GetTexture("_MainTex"));
                dst.SetTextureScale("_MainTex", src.GetTextureScale("_MainTex"));
                dst.SetTextureOffset("_MainTex", src.GetTextureOffset("_MainTex"));
            }
            else if (src.HasProperty("_BaseMap"))
            {
                dst.SetTexture("_MainTex", src.GetTexture("_BaseMap"));
                dst.SetTextureScale("_MainTex", src.GetTextureScale("_BaseMap"));
                dst.SetTextureOffset("_MainTex", src.GetTextureOffset("_BaseMap"));
            }

            if (src.HasProperty("_Color")) dst.SetColor("_Color", src.GetColor("_Color"));
            else if (src.HasProperty("_BaseColor")) dst.SetColor("_Color", src.GetColor("_BaseColor"));

            if (src.HasProperty("_BumpMap")) dst.SetTexture("_NormalTex", src.GetTexture("_BumpMap"));
            else if (src.HasProperty("_NormalTex")) dst.SetTexture("_NormalTex", src.GetTexture("_NormalTex"));

            if (src.HasProperty("_SpecColor") || src.HasProperty("_SpecGlossMap"))
            {
                dst.EnableKeyword("GTRT_WORKFLOW_SPECULAR");
                if (src.HasProperty("_SpecGlossMap")) dst.SetTexture("_SpecularTex", src.GetTexture("_SpecGlossMap"));
                if (src.HasProperty("_SpecColor")) dst.SetColor("_SpecColor", src.GetColor("_SpecColor"));
            }
            else
            {
                if (src.HasProperty("_MetallicGlossMap")) dst.SetTexture("_MetallicTex", src.GetTexture("_MetallicGlossMap"));
                else if (src.HasProperty("_MetallicTex")) dst.SetTexture("_MetallicTex", src.GetTexture("_MetallicTex"));

                if (src.HasProperty("_Metallic")) dst.SetFloat("_Metallic", src.GetFloat("_Metallic"));
            }

            if (src.HasProperty("_Glossiness")) dst.SetFloat("_Smoothness", src.GetFloat("_Glossiness"));
            else if (src.HasProperty("_Smoothness")) dst.SetFloat("_Smoothness", src.GetFloat("_Smoothness"));
            else if (src.HasProperty("_Roughness")) dst.SetFloat("_Smoothness", 1.0f - src.GetFloat("_Roughness"));

            if (src.HasProperty("_EmissionColor") || src.HasProperty("_EmissionMap"))
            {
                if (src.HasProperty("_EmissionColor")) dst.SetVector("_EmissionColor", src.GetVector("_EmissionColor"));
            }

            if (EnableAlphaClip)
            {
                if (src.HasProperty("_Cutoff")) dst.SetFloat("_Cutoff", src.GetFloat("_Cutoff"));
                else if (src.HasProperty("_AlphaCutoff")) dst.SetFloat("_Cutoff", src.GetFloat("_AlphaCutoff"));

                bool isAlphaTest = src.IsKeywordEnabled("_ALPHATEST_ON") || src.renderQueue == (int)RenderQueue.AlphaTest;

                if (isAlphaTest) dst.EnableKeyword("GTRT_ALPHA_CLIP");
            }

            dst.SetInteger("_RendererInstanceID", objID);
            return dst;
        }

        public void Process(Renderer renderer)
        {
            var mats = renderer.sharedMaterials;
            int objID = renderer.GetInstanceID();
            bool changed = false;
            for (int i = 0; i < mats.Length; i++)
            {
                var m = mats[i];
                var newMat = BindSSRTShadowMat(m, objID);

                if (!ReferenceEquals(m, newMat))
                {
                    mats[i] = newMat;
                    changed = true;
                }
            }
            if (changed)
            {
                renderer.sharedMaterials = mats;
            }

            renderer.forceRenderingOff = true;
        }
    }
}