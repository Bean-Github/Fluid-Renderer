Shader "Custom/Particle"
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
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 color : COLOR0;
            };

            uniform float4x4 _ObjectToWorld;
            uniform float _NumInstances;

            uniform float maxVelocity;
                        
            uniform float4 _TopColor;
            uniform float4 _MediumColor;
            uniform float4 _BottomColor;

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


            v2f vert(appdata_base v, uint instanceID : SV_InstanceID)
            {
                v2f o;

                float3 particlePos = particles[instanceID].position;
                float r = particles[instanceID].radius;
                float3 scaledVertex = v.vertex.xyz * r;

                float4 wpos = float4(particlePos + scaledVertex, 1.0);

                o.pos = mul(UNITY_MATRIX_VP, wpos);
                o.color = float4(instanceID / _NumInstances, 0.0f, 0.0f, 0.0f);


                float speed = length(particles[instanceID].velocity);

                // we send a 4x4 matrix which defines, postion, rotation and scale
                float colorT = speed / maxVelocity;

                if (colorT < 0.33)
                    o.color = lerp(_BottomColor, _MediumColor, colorT * 3.0);
                else if (colorT < 0.66)
                    o.color = lerp(_MediumColor, _TopColor, (colorT - 0.33) * 3.0);
                else
                    o.color = lerp(_BottomColor, _TopColor, colorT);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                return i.color;
            }
            ENDCG
        }
    }
}


