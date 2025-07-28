Shader "Custom/RaymarchTest"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
                HLSLPROGRAM

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _  _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


            //Boilerplate code, we aren't doind anything with our vertices or any other input info,
            // because technically we are working on a quad taking up the whole screen
            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            

            real frag (v2f i) : SV_Target
            {
                return float4(1.0, 0.0, 0.0, 1.0).r; // Return a red color for testing)
            }
            ENDHLSL
        }
    }
}