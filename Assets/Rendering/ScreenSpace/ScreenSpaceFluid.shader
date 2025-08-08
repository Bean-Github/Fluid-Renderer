Shader "Custom/ParticleSSRender"
{
    Properties
    {
        _TopColor ("Top Color", Color) = (1,0,0,1)
        _MediumColor ("Medium Color", Color) = (0,1,0,1)
        _BottomColor ("Bottom Color", Color) = (0,0,1,1)
    }

    SubShader
    {
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float4 color : COLOR0;

                //float2 uv : TEXCOORD0;
            };

            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };


            uniform float4x4 _ObjectToWorld;
            uniform float _NumInstances;

            uniform float maxVelocity;
                        
            uniform float4 _TopColor;
            uniform float4 _MediumColor;
            uniform float4 _BottomColor;

            
            TEXTURE2D_X(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            

            float4x4 _CameraToWorld;
            float4x4 _CameraInvProjection;


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

            struct Ray {
                float3 origin;
                float3 direction;
            };

            Ray CreateRay(float3 o, float3 d)
            {
                Ray ray;
                ray.origin = o;
                ray.direction = normalize(d);
                return ray;
            }

            // Reconstruct ray direction from UV
            Ray GetRay(float2 uv) {
                
                // construct ray per pixel
                const float2 ndc = uv * 2.0 - 1.0; // 0..1 UV -> -1..1 NDC

                const float4 clip = float4(ndc, 0, -1); // clip space point

                // project clip space to view space (2d to 3d)
                float4 viewPos = mul(_CameraInvProjection, clip);  // still homogenous coordinates (non-singular w)
                viewPos /= abs(viewPos.w) + 1e-6;  // perspective divide
                
                // view space is a world space with camera at origin, looking down -Z axis

                // convert from camera space to world space (can ignore w now)
                const float3 rayDirWS = normalize(mul(_CameraToWorld, float4(viewPos.xyz, 0)).xyz);  
                const float3 rayOriginWS = GetCameraPositionWS();

                return CreateRay(rayOriginWS, rayDirWS);
            }

            Varyings vert(appdata v, uint vertexID : SV_VertexID)
            {
                Varyings o;

                float3 particlePos = particles[vertexID].position;
                float r = particles[vertexID].radius;
                float3 scaledVertex = v.vertex.xyz * r;

                float4 wpos = float4(particlePos + scaledVertex, 1.0);

                o.pos = mul(UNITY_MATRIX_VP, wpos);
                o.color = float4(vertexID / _NumInstances, 0.0f, 0.0f, 0.0f);


                float speed = length(particles[vertexID].velocity);

                // we send a 4x4 matrix which defines, postion, rotation and scale
                float colorT = speed / maxVelocity;

                if (colorT < 0.33)
                    o.color = lerp(_BottomColor, _MediumColor, colorT * 3.0);
                else if (colorT < 0.66)
                    o.color = lerp(_MediumColor, _TopColor, (colorT - 0.33) * 3.0);
                else
                    o.color = lerp(_BottomColor, _TopColor, colorT);

                // Fullscreen triangle (no mesh needed)

                // float2 uvs[3] = {
                //     float2(0, 1),
                //     float2(2, 1),
                //     float2(0, -1)
                // };

                // // // clip-space position
                // // o.positionCS = float4(positions[vertexID], 0, 1);
                
                // float2 uv = uvs[vertexID];
                // o.uv = uv;

                return o;
            }


            float4 frag(Varyings input) : SV_Target
            {

                //Ray ray = GetRay(input.uv);

                // // calculate the depth
                // float nonLinearDepthTexture = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // // get world linear value from depth texture
                // float depthTexture = LinearEyeDepth(nonLinearDepthTexture, _ZBufferParams) * length(ray.direction);

                return input.color;
            }
            ENDHLSL
        }
    }
}


