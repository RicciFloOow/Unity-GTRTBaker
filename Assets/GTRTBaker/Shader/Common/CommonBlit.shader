Shader "GTRTBaker/Common/CommonBlit"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "Common Blit Color"

            HLSLPROGRAM
            #pragma vertex ProcTriangleVertex
            #pragma fragment frag

            #include "../Lib/ProceduralMesh.hlsl"

            Texture2D<float4> _MainTex;

            half4 frag (ProcTriVaryings input) : SV_Target
            {
                int2 pos = int2(input.positionCS.xy);
                return _MainTex.Load(int3(pos, 0));
            }
            ENDHLSL
        }
    }
}
