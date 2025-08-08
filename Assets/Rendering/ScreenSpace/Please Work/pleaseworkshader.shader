Shader "Fluid/ParticleDepthOnly"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Background" }
        ZWrite On
        ZTest LEqual
        Cull Off

        Pass
        {
            Name "DepthOnly"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float scale;

            struct Particle
            {
                float3 position;
                float3 velocity;
                float radius;
                float3 predictedPosition;
                float density;
                float nearDensity;
            };

            StructuredBuffer<Particle> particles;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 clippos : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes v, uint instanceID : SV_InstanceID)
            {
                Varyings o;

                float3 particlePos = particles[instanceID].position;
                float3 vertOffset = v.positionOS.xyz * particles[instanceID].radius * 2;

                float3 camUp = unity_CameraToWorld._m01_m11_m21;
                float3 camRight = unity_CameraToWorld._m00_m10_m20;

                float3 vertPosWorld = particlePos + camRight * vertOffset.x + camUp * vertOffset.y;

                o.clippos = TransformWorldToHClip(vertPosWorld);
                o.worldPos = vertPosWorld;
                o.uv = v.uv;

                return o;
            }

            float LinearDepthToUnityDepth(float linearDepth)
            {
                float depth01 = (linearDepth - _ProjectionParams.y) / (_ProjectionParams.z - _ProjectionParams.y);
                return (1.0 - (depth01 * _ZBufferParams.y)) / (depth01 * _ZBufferParams.x);
            }

            float4 frag(Varyings i, out float outDepth : SV_Depth) : SV_Target
            {
                float2 centerOffset = (i.uv - 0.5) * 2;
                float sqrDst = dot(centerOffset, centerOffset);
                if (sqrDst > 1.0) discard;

                float z = sqrt(1.0 - sqrDst);

                float dcam = distance(i.worldPos, _WorldSpaceCameraPos);
                float linearDepth = dcam - z * scale;
                outDepth = LinearDepthToUnityDepth(linearDepth);

                outDepth = 1;

                return float4(0, 0, 0, 0); // No color needed
            }

            ENDHLSL
        }
    }
}
