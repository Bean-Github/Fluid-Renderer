// Upgrade NOTE: commented out 'float4x4 _CameraToWorld', a built-in variable


Shader "Custom/RaymarchShader"
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
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            //float4x4 _CameraToWorld;
            float4x4 _CameraInverseProjection;
            float4x4 _ObjectToWorld;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                    
                float3 viewVector : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                float4 worldPos = mul(_ObjectToWorld, v.vertex);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                // reconstruct view vector from screen UV

                // v.uv is in [0,1] range with 0.5 at center, so we convert to [-1, 1] range
                // z = 0 and w = -1 are placeholders
                // multiply with camera inverse projection to convert to view space (a 3D point on the near clip plane).
                // makes a vector pointing from the camera origin to the pixel on the near plane, in view space.
                float3 viewVector = mul(_CameraInverseProjection, float4(v.uv * 2 - 1, 0, -1));

                //NDC to View Space: The inverse projection matrix "unprojects" the 2D pixel into 3D space.

                //View Space to World Space: The camera-to-world matrix rotates the direction into global coordinates.
                // go from view space to world space
                o.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

                return o;
            }


            sampler2D _MainTex;
            float4 _MainTex_ST;

            
            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/

                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection

                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection

                // CASE 3: ray misses box (dstA > dstB)

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            // v2f vert (appdata v)
            // {
            //     v2f o;
            //     o.vertex = UnityObjectToClipPos(v.vertex);
            //     o.uv = TRANSFORM_TEX(v.uv, _MainTex);
            //     UNITY_TRANSFER_FOG(o,o.vertex);
            //     return o;
            // }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                // apply fog
                // UNITY_APPLY_FOG(i.fogCoord, col);
                return float4(1,0,0,1);
            }
            ENDCG
        }
    }
}

