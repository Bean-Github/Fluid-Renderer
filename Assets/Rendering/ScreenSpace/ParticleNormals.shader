Shader "Fluid/ParticleNormals" {

	SubShader {

		Tags {"Queue"="Geometry" }
		Cull Off
		
		Pass {

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.5
			#include "UnityCG.cginc"
			
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

			struct v2f
			{
				float4 clippos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 posWorld : TEXCOORD1;
			};

			// appdata_base is the input data for a single vertex
			// assume the particle uses a plane (billboard rendering) with (-0.5 to 0.5) range
			v2f vert (appdata_base v, uint instanceID : SV_InstanceID)
			{
				v2f o;
				
				float3 particlePos = particles[instanceID].position;
				float3 vertOffset = v.vertex * particles[instanceID].radius * 2;

				float3 camUp = unity_CameraToWorld._m01_m11_m21;
				float3 camRight = unity_CameraToWorld._m00_m10_m20;

				// the vertex positions on the plane are scaled by camRight and camUp so they always face camera
				float3 vertPosWorld = particlePos + camRight * vertOffset.x + camUp * vertOffset.y;

				// world position to clip space
				o.clippos = mul(UNITY_MATRIX_VP, float4(vertPosWorld, 1));
				o.posWorld = vertPosWorld;
				o.uv = v.texcoord;  // uv coord of mesh given by appdata_base

				return o;  // return the vertex after modifying
			}

			// https://www.vertexfragment.com/ramblings/unity-custom-depth/
			float LinearDepthToUnityDepth(float linearDepth)
			{
				// _ProjectionParams.y = near plane
				// _ProjectionParams.z = far plane
				float depth01 = (linearDepth - _ProjectionParams.y) / (_ProjectionParams.z - _ProjectionParams.y);

				// voodoo, converts to nonlinear, unity depth is nonlinear and reversed on many platforms
				return (1.0 - (depth01 * _ZBufferParams.y)) / (depth01 * _ZBufferParams.x);  
			}

			// make the billboard look like a sphere
			float4 frag (v2f i, out float Depth : SV_Depth) : SV_Target
			{
				float2 centerOffset = (i.uv - 0.5) * 2;
				float sqrDst = dot(centerOffset, centerOffset);  // discard pixels outside a circle
				if (sqrDst > 1) discard;

				// z = sqrt(1 - x^2 - y^2)
				float z = sqrt(1-sqrDst);

				float dcam = length(i.posWorld - _WorldSpaceCameraPos); // distance of vertex to camera

				// subtract by scaled z to color like a sphere! (imagine a 3d parabola going into camera)
				float linearDepth = dcam - z * scale;

				Depth = LinearDepthToUnityDepth(linearDepth);
				
				return (1 - Depth) / 2;
			}

			ENDCG
		}
	}
}



