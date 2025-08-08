Shader "Custom/GaussianBlurBlit"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off

        Pass
        {
            Name "GaussianBlurPassHorizontal"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            //#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "GaussCalculations.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D_X(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            float4 _CameraOpaqueTexture_TexelSize;

            TEXTURE2D_X(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            float4 _CameraDepthTexture_TexelSize;

            float4 GaussianBlur(float2 uv, int blurSize, float blurSmoothness)
            {
                float4 sum = 0;
                float weightSum = 0;

                // blur size is like "radius" from the center pixel
                int kernelSize = blurSize * 2 + 1;

                float sigma;/*  = kernelSize / (6 * max(0.001f, blurSmoothness)); */

                float depth = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv).a;

                // TODO: UNDERSTAND WHAT THIS SHIT IS
                int radiusInt = ceil(blurSize);
                float radiusFloat = CalculateScreenSpaceRadius(blurSize, depth, _CameraOpaqueTexture_TexelSize.z);
                if (radiusInt <= 1 && blurSize > 0) blurSize = 2;
                radiusInt = min(1920, blurSize);
                float fR = max(0, blurSize - radiusFloat); 
                sigma = max(0.0000001, (blurSize - fR) / (6 * max(0.001f, blurSmoothness)));

                float centerDepth = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv);


                for (int offsetX = -blurSize; offsetX <= blurSize; offsetX++)
                {
                    float2 uv2 = uv + float2(offsetX, 0) * _CameraOpaqueTexture_TexelSize.xy;
                    float4 sample = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv2);

                    float sampleDepth = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv2);

                    float depthDifference = (centerDepth - sampleDepth) * _DepthFactor;

                    float depthWeight = exp(-depthDifference * depthDifference);
                    float gaussWeight = GaussianBlurWeight(offsetX, 0, sigma);
                    float totalWeight = gaussWeight * depthWeight;

                    weightSum += totalWeight;

                    sum += sample * totalWeight;
                }

                return sum / weightSum;
            }


            // rendering to screen
            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                
                // If ray misses box, return the color from the camera opaque texture
                //return SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);

                return GaussianBlur(input.uv, _BlurSize, _BlurSmoothness);
            }

            ENDHLSL

        }

        Pass
        {
            Name "GaussianBlurPassVertical"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            //#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "GaussCalculations.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D_X(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_TexelSize;


            // TODO: the particles are not actually put into the depth
            
            float4 GaussianBlur(float2 uv, int blurSize, float blurSmoothness)
            {
                float4 sum = 0;
                float weightSum = 0;
                float depth = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, uv).a;

                // blur size is like "radius" from the center pixel
                int kernelSize = blurSize * 2 + 1;

                float sigma;/*  = kernelSize / (6 * max(0.001f, blurSmoothness)); */

                int radiusInt = ceil(blurSize);
                float radiusFloat = CalculateScreenSpaceRadius(blurSize, depth, _MainTex_TexelSize.z);
                if (radiusInt <= 1 && blurSize > 0) blurSize = 2;
                radiusInt = min(1920, blurSize);
                float fR = max(0, blurSize - radiusFloat); 
                sigma = max(0.0000001, (blurSize - fR) / (6 * max(0.001f, blurSmoothness)));

                float centerDepth = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, uv);

                for (int offsetY = -blurSize; offsetY <= blurSize; offsetY++)
                {
                    float2 uv2 = uv + float2(0, offsetY) * _MainTex_TexelSize.xy;
                    float4 sample = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, uv2);

                    float sampleDepth = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, uv2);

                    float depthDifference = (centerDepth - sampleDepth) * _DepthFactor;

                    float depthWeight = exp(-depthDifference * depthDifference);
                    float gaussWeight = GaussianBlurWeight(0, offsetY, sigma);
                    float totalWeight = gaussWeight * depthWeight;

                    weightSum += totalWeight;
                    sum += sample * totalWeight;
                }

                return sum / weightSum;
            }


            // rendering to screen
            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                
                // float4 worldColor = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, input.uv);

                // If ray misses box, return the color from the camera opaque texture
                return GaussianBlur(input.uv, _BlurSize, _BlurSmoothness);
            }

            ENDHLSL

        }

        Pass
        {
            Name "Normals"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            //#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            // gets the lighting stuff
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "GaussCalculations.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D_X(_DepthMap);
            SAMPLER(sampler_DepthMap);
            float4 _DepthMap_TexelSize;

            

            float GetWorldDepth(float encodedDepth)
            {
                // return 1.0 / (_ZBufferParams.x * encodedDepth + _ZBufferParams.y);
                float depthWorld = lerp(_ProjectionParams.y, _ProjectionParams.z, encodedDepth);
                return depthWorld;
            }

            // Calculate view-space position by sampling depth map at given uv coordinate
            float3 ViewPos(float2 uv)
            {
                float4 depthInfo = SAMPLE_TEXTURE2D_X(_DepthMap, sampler_DepthMap, uv);
                bool useSmoothedDepth = true;
                float depth = useSmoothedDepth ? depthInfo.r : depthInfo.a;

                if (depth == 0.0) {
                    discard;
                }

                float worldDepth = GetWorldDepth(depth);

                float3 origin = 0;

                float2 ndc = uv * 2.0 - 1.0;

                float4 viewVector = mul(_CameraInvProjection, float4(ndc, 0, 1));
                float3 viewDir = normalize(viewVector.xyz / viewVector.w);


                return float3(origin + viewDir * worldDepth);
            }

            float3 ViewNormal(float2 uv, float2 stepSize)
            {
                float3 posCenter = ViewPos(uv);

                // Check for infinite depth and discard if so
                if (dot(posCenter, posCenter) == 1.#INF)
                    discard;

                float3 origin = _WorldSpaceCameraPos;
                //float2 o = _MainTex_TexelSize.xy;

                float3 ddx = ViewPos(uv + float2(stepSize.x, 0)) - posCenter;
                float3 ddx2 = posCenter - ViewPos(uv + float2(-stepSize.x, 0));
                if (abs(ddx2.z) < abs(ddx.z))
                {
                    ddx = ddx2;
                }
                
                float3 ddy = ViewPos(uv + float2(0, stepSize.y)) - posCenter;
                float3 ddy2 = posCenter - ViewPos(uv + float2(0,-stepSize.y));
                if (abs(ddy2.z) < abs(ddy.z)) {
                    ddy = ddy2;
                }

                // float3 ddx1 = ViewPos(uv + float2(stepSize.x, 0)) - posCenter;
                // float3 ddx2 = ViewPos(uv - float2(stepSize.x, 0)) - posCenter;
                // float3 ddy1 = ViewPos(uv + float2(0, stepSize.y)) - posCenter;
                // float3 ddy2 = ViewPos(uv - float2(0, stepSize.y)) - posCenter;

                // // Combine and average them
                // float3 ddx = (ddx1 + ddx2) * 0.5;
                // float3 ddy = (ddy1 + ddy2) * 0.5;

                float3 viewNormal = normalize(cross(ddy, ddx));
                // Compute view-space normal, then transform to world space
                //float3 viewNormal = normalize(cross(ddy, ddx));
                 
                return viewNormal;
            }


            // TODO: apply gaussian blur over the normals?
            float4 frag(Varyings i) : SV_Target
            {
                float2 stepSize = _DepthMap_TexelSize.xy * 5;
                
                float3 n0 = normalize(ViewNormal(i.uv, stepSize));
                float3 n1 = normalize(ViewNormal(i.uv + float2(stepSize.x, 0), stepSize));
                float3 n2 = normalize(ViewNormal(i.uv + float2(0, stepSize.y), stepSize));
                float3 n3 = normalize(ViewNormal(i.uv - float2(stepSize.x, 0), stepSize));
                float3 n4 = normalize(ViewNormal(i.uv - float2(0, stepSize.y), stepSize));

                float3 viewNormal = normalize(n0 + n1 + n2 + n3 + n4);

                float3 worldNormal = mul(_CameraToWorld, float4(viewNormal, 0));
                float3 encodedNormal = normalize(worldNormal) * 0.5 + 0.5;

                return float4(encodedNormal, 1.0);

                return float4(normalize(-worldNormal), 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "Rendering"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            //#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            // gets the lighting stuff
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "GaussCalculations.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D_X(_ColorTex);
            SAMPLER(sampler_ColorTex);
            float4 _ColorTex_TexelSize;

            TEXTURE2D_X(_DepthMap);
            SAMPLER(sampler_DepthMap);
            float4 _DepthMap_TexelSize;

            // get normalized view dir from uv
            float3 GetRay(float2 uv) {

                // construct ray per pixel
                const float2 ndc = uv * 2.0 - 1.0; // 0..1 UV -> -1..1 NDC

                const float4 clip = float4(ndc, 0, 1.0); // clip space point
                 // project clip space to view space (2d to 3d)
                float4 viewPos = mul(_CameraInvProjection, clip);  // still homogenous coordinates (non-singular w)
                viewPos /= abs(viewPos.w) + 1e-6;  // perspective divide
                // view space is a world space with camera at origin, looking down -Z axis

                // convert from camera space to world space (can ignore w now)
                const float3 rayDirWS = normalize(mul(_CameraToWorld, float4(viewPos.xyz, 0)).xyz);  

                return rayDirWS;
            }

            float GetWorldDepth(float encodedDepth)
            {
                // return 1.0 / (_ZBufferParams.x * encodedDepth + _ZBufferParams.y);
                float depthWorld = lerp(_ProjectionParams.y, _ProjectionParams.z, encodedDepth);
                return depthWorld;
            }

            // LIGHTING CALCULATIONS from the raymarching earlier
            struct LightResponse
            {
                float3 refractDir;
                float3 reflectDir;
                
                float refractStrength; // 0..1
                float reflectStrength; // 0..1
            };

            // Calculate the proportion of light that is reflected at the boundary between two media (via the fresnel equations)
            // Note: the amount of light refracted can be calculated as 1 minus this value
            float CalculateReflectance(float3 inDir, float3 normal, float iorA, float iorB)
            {
                float refractRatio = iorA / iorB;
                float cosAngleIn = -dot(inDir, normal);
                float sinSqrAngleOfRefraction = refractRatio * refractRatio * (1 - cosAngleIn * cosAngleIn);
                if (sinSqrAngleOfRefraction >= 1) return 1; // Ray is fully reflected, no refraction occurs

                float cosAngleOfRefraction = sqrt(1 - sinSqrAngleOfRefraction);
                // Perpendicular polarization
                float rPerpendicular = (iorA * cosAngleIn - iorB * cosAngleOfRefraction) / (iorA * cosAngleIn + iorB * cosAngleOfRefraction);
                rPerpendicular *= rPerpendicular;
                // Parallel polarization
                float rParallel = (iorB * cosAngleIn - iorA * cosAngleOfRefraction) / (iorB * cosAngleIn + iorA * cosAngleOfRefraction);
                rParallel *= rParallel;

                // Return the average of the perpendicular and parallel polarizations
                return (rPerpendicular + rParallel) / 2;
            }

            LightResponse CalculateRefractionAndReflection(float3 inVec, float3 normal, float iorA, float iorB)
            {
                LightResponse response;

                // Calculate theta1
                const float theta1 = acos(dot(-inVec, normal)); // angle of incidence, assume inVec and normal are normalized

                // Calculate theta2 using Snell's Law
                const float theta2 = asin((iorA / iorB) * sin(theta1));

                // Calculate refraction direction
                response.refractDir = normalize((iorA / iorB) * inVec + (iorA / iorB * cos(theta1) - cos(theta2)) * normal);

                // Calculate reflection direction
                response.reflectDir = reflect(inVec, normal);

                // Calculate reflection and refraction strengths
                // float R0 = pow((iorA - iorB) / (iorA + iorB), 2); // Fresnel reflectance at normal incidence
                // float R = R0 + (1 - R0) * pow(1 - cos(theta1), 5); // Fresnel reflectance for arbitrary angle
                response.reflectStrength = CalculateReflectance(inVec, normal, iorA, iorB); // Reflection strength
                response.refractStrength = 1.0 - response.reflectStrength; // Refraction strength

                return response; // Placeholder for now
            }
            
            float3 DirToSun()
            {
                Light mainLight = GetMainLight();
                float3 lightDir = -mainLight.direction; // Already normalized, world-space
                return lightDir;
            }

            float3 SampleSky(float3 dir)
            {
                const float3 colGround   = float3(0.35, 0.3, 0.35) * 0.53;
                const float3 colSkyHorizon  = float3(1, 1, 1);
                const float3 colSkyZenith = float3(0.08, 0.37, 0.73);

                float sun = pow(max(0, dot(dir, -DirToSun())), 500) * 1;
                float skyGradientT = pow(smoothstep(0, 0.4, dir.y), 0.35);
                float groundToSkyT = smoothstep(-0.01, 0, dir.y);
                float3 skyGradient = lerp(colSkyHorizon, colSkyZenith, skyGradientT);

                return lerp(colGround, skyGradient, groundToSkyT) + sun * (groundToSkyT >= 1);
            }

            float3 Environment(float3 worldDir)
            {
                // --- Floor parameters ---
                const float floorHeight = -5.0;             // y = 0 plane
                const float3 floorColor = float3(0.05, 0.05, 0.06); // dark gray/blueish
                const float3 cameraPos = _WorldSpaceCameraPos.xyz;

                // Ray origin and direction
                float3 rayOrigin = cameraPos;
                float3 rayDir = normalize(worldDir);

                // --- Ray-plane intersection: y = floorHeight ---
                // Solves: rayOrigin.y + t * rayDir.y = floorHeight
                float t = (floorHeight - rayOrigin.y) / rayDir.y;

                if (t > 0.0) // hit floor in front of camera
                {
                    float3 hitPos = rayOrigin + t * rayDir;

                    // Simple checker pattern
                    float2 checkerUV = hitPos.xz * 0.5;
                    float checker = fmod(floor(checkerUV.x) + floor(checkerUV.y), 2.0);
                    float3 color = lerp(floorColor, floorColor * 1.2, checker);

                    return color;
                }

                // --- Sky ---
                return SampleSky(worldDir);
            }
            
            float3 CalculateClosestFaceNormal(float3 boxSize, float3 p)
            {
                float3 halfSize = boxSize * 0.5;
                float3 o = (halfSize - abs(p));
                return (o.x < o.y && o.x < o.z) ? float3(sign(p.x), 0, 0) : (o.y < o.z) ? float3(0, sign(p.y), 0) : float3(0, 0, sign(p.z));
            }
            float4 SmoothEdgeNormals(float3 normal, float3 pos, float3 boxSize)
            {
                // Smoothly flatten normals out at boundary edges
                float3 o = boxSize / 2 - abs(pos);
                float faceWeight = max(0, min(o.x, o.z));
                float3 faceNormal = CalculateClosestFaceNormal(boxSize, pos);
                const float smoothDst = 0.01;
                const float smoothPow = 5;
                //faceWeight = (1 - smoothstep(0, smoothDst, faceWeight)) * (1 - pow(saturate(normal.y), smoothPow));
                float cornerWeight = 1 - saturate(abs(o.x - o.z) * 6);
                faceWeight = 1 - smoothstep(0, smoothDst, faceWeight);
                faceWeight *= (1 - cornerWeight);

                return float4(normalize(normal * (1 - faceWeight) + faceNormal * (faceWeight)), faceWeight);
            }

            // PROBLEM: cannot encode negative normals in camera texture :()

            float4 frag(Varyings i) : SV_Target
            {
                float3 viewDir = GetRay(i.uv);

                // TODO: smooth the normal along simulation bounds edges
                float3 encodedNormal = SAMPLE_TEXTURE2D_X(_ColorTex, sampler_ColorTex, i.uv).xyz;
                float3 normal = encodedNormal * 2.0 - 1.0;

                float4 depthInfo = SAMPLE_TEXTURE2D_X(_DepthMap, sampler_DepthMap, i.uv);
                //return float4(viewDir, 0);

                if (depthInfo.r == 0.0f)
                {
                    return float4(Environment(viewDir), 0);
                }

                float worldDepth = GetWorldDepth(depthInfo.r);
                float3 hitPos = _WorldSpaceCameraPos.xyz + viewDir * worldDepth;

                normal = SmoothEdgeNormals(normal, hitPos, float3(10, 8.8, 6));   // TODO: undetstand how this works???

                float3 lightDir = DirToSun();


                float shading = dot(normal, lightDir) * 0.5f + 0.5f;


                LightResponse response = CalculateRefractionAndReflection(viewDir, normal, 1.00f, 1.33f);  // 1.0 air, 1.33 water



                float3 scatterCoeff = float3(1.0f, 1.1f, 1.5f);

                float3 reflectLight = Environment(response.reflectDir);
                float3 refractLight = Environment(response.refractDir) * response.refractStrength;

                return float4(reflectLight * scatterCoeff * shading, 0);

                return float4((reflectLight + refractLight) * scatterCoeff * shading, 0);

            }

            ENDHLSL
        }
    }
}
