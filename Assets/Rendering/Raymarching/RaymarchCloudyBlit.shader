Shader "Custom/RaymarchBlit"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off

        Pass
        {
            Name "RaymarchBlitPass"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            //#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            // gets the lighting stuff
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D_X(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);


            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // sampler2D _MainTex;
            // float4 _MainTex_ST;

            TEXTURE2D_X(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);


            float4x4 _CameraToWorld;
            float4x4 _CameraInvProjection;

            Varyings vert(uint vertexID : SV_VertexID)
            {
                Varyings o;

                // Fullscreen triangle (no mesh needed)
                float2 positions[3] = {
                    float2(-1, -1),
                    float2( 3, -1),
                    float2(-1,  3)
                };

                float2 uvs[3] = {
                    float2(0, 1),
                    float2(2, 1),
                    float2(0, -1)
                };

                // clip-space position
                o.positionCS = float4(positions[vertexID], 0, 1);
                
                float2 uv = uvs[vertexID];
                o.uv = uv;

                return o;
            }

            // -- // -- //
            // VALUES
            // -- // -- //


            float _StepSize;
            int _NumRefractions;

            float _LightStepSize;

            float _DensityMultiplier;

            float3 _ScatteringCoefficients;


            // misc
            float volumeValueOffset;
            float _Intensity;
            float3 _BoxBoundsMin;
            float3 _BoxBoundsMax;

            TEXTURE3D(_DensityMap);
            SAMPLER(sampler_DensityMap);

            // -- // -- //

            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            // dstInsideBox is the distance that the ray will travel while running inside the box
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/

                float3 safeDiv = rayDir == 0 ? 1e-6 : rayDir;

                float3 t0 = (boundsMin - rayOrigin) / safeDiv;
                float3 t1 = (boundsMax - rayOrigin) / safeDiv;
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

            // STRUCTS //
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

            struct HitInfo
            {
                bool didHit;
                bool isInsideFluid; // true if ray is entering fluid, false if ray is exiting fluid (regarding boundary)

                float3 hitPoint;
                float3 normal;

                float densityAlongRay;
            };

            struct LightResponse
            {
                float3 refractDir;
                float3 reflectDir;
                
                float refractStrength; // 0..1
                float reflectStrength; // 0..1
            };
            // -- // -- //

            
            // CALCULATIONS //
            float SampleDensity(float3 pos)
            {
                float3 boundsSize = _BoxBoundsMax - _BoxBoundsMin;

                // convert world position to [0-1] UVW range
                float3 uvw = (pos - _BoxBoundsMin) / (_BoxBoundsMax - _BoxBoundsMin);

                // if uvw is epsilon away from 0 or 1, then return -volumeValueOffset (-150, large negative) to cut out fuzzy edges
                const float epsilon = 0.0001;
                bool isEdge = any(uvw >= 1 - epsilon || uvw <= epsilon);
                if (isEdge) return -volumeValueOffset;

                // sample the 3d texture by the [0-1] UVW coordinate range
                return _DensityMap.SampleLevel(sampler_DensityMap, uvw, 0).r;
            }

            float3 CalculateClosestFaceNormal(float3 boxSize, float3 p)
            {
                float3 halfSize = boxSize * 0.5;
                float3 o = (halfSize - abs(p));
                return (o.x < o.y && o.x < o.z) ? float3(sign(p.x), 0, 0) : (o.y < o.z) ? float3(0, sign(p.y), 0) : float3(0, 0, sign(p.z));
            }

            float3 CalculateNormal(float3 pos)
            {
                float3 boundsSize = _BoxBoundsMax - _BoxBoundsMin;

                float3 uvw = (pos + boundsSize * 0.5) / boundsSize;

                const float s = 0.1;
                float3 offsetX = float3(1, 0, 0) * s;
                float3 offsetY = float3(0, 1, 0) * s;
                float3 offsetZ = float3(0, 0, 1) * s;

                float dx = SampleDensity(pos - offsetX) - SampleDensity(pos + offsetX);
                float dy = SampleDensity(pos - offsetY) - SampleDensity(pos + offsetY);
                float dz = SampleDensity(pos - offsetZ) - SampleDensity(pos + offsetZ);

                float3 volumeNormal = normalize(float3(dx, dy, dz));

                // Smoothly flatten normals out at boundary edges
                float3 o = boundsSize / 2 - abs(pos);
                float faceWeight = min(o.x, min(o.y, o.z));
                float3 faceNormal = CalculateClosestFaceNormal(boundsSize, pos);
                const float smoothDst = 0.3;
                const float smoothPow = 5;
                faceWeight = (1 - smoothstep(0, smoothDst, faceWeight)) * (1 - pow(saturate(volumeNormal.y), smoothPow));

                return normalize(volumeNormal * (1 - faceWeight) + faceNormal * (faceWeight));
            }

            bool IsInsideFluid(float3 pos)
            {
                float2 boundsDstInfo = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, pos, float3(0, 0, 1));
                return (boundsDstInfo.x <= 0 && boundsDstInfo.y > 0) && SampleDensity(pos) > 0;
            }

            LightResponse CalculateRefractionAndReflection(float3 inVec, float3 normal, float iorA, float iorB)
            {
                LightResponse response;

                // Calculate theta1
                float theta1 = acos(dot(-inVec, normal)); // angle of incidence, assume inVec and normal are normalized

                // Calculate theta2 using Snell's Law
                float theta2 = asin((iorA / iorB) * sin(theta1));

                // Calculate refraction direction
                response.refractDir = normalize((iorA / iorB) * inVec + (iorA / iorB * cos(theta1) - cos(theta2)) * normal);

                // Calculate reflection direction
                response.reflectDir = reflect(inVec, normal);

                // Calculate reflection and refraction strengths
                float R0 = pow((iorA - iorB) / (iorA + iorB), 2); // Fresnel reflectance at normal incidence
                float R = R0 + (1 - R0) * pow(1 - cos(theta1), 5); // Fresnel reflectance for arbitrary angle
                response.reflectStrength = R; // Reflection strength
                response.refractStrength = 1.0 - R; // Refraction strength

                return response; // Placeholder for now
            }
            
            float CalculateDensityAlongRay(float3 origin, float3 direction, float stepSize)
            {
                float density = 0.0;

                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, origin, direction);
                float dstToBox = hit.x;
                float dstInsideBox = hit.y;

                if (dstInsideBox == 0.0f) {
                    // Ray does not intersect box, return 0 density
                    return 0.0f;
                }

                float dstTraveled = 0.0f;

                float nudge = stepSize * 0.5;
                float3 entryPos = origin + direction * (dstToBox);
                dstInsideBox -= (nudge + 0.01f);

                float3 rayPos = entryPos;

                // while ray is still inside 
                while (dstTraveled < dstInsideBox)
                {
                    rayPos = entryPos + direction * dstTraveled;
                    dstTraveled += stepSize;
                    
                    float densityAlongStep = SampleDensity(rayPos) * stepSize * _DensityMultiplier;

                    density += densityAlongStep;
                }

                return density;
            }
            // -- // -- //


            // Reconstruct ray direction from UV
            Ray GetRay(float2 uv) {
                
                // construct ray per pixel
                float2 ndc = uv * 2.0 - 1.0; // 0..1 UV -> -1..1 NDC

                float4 clip = float4(ndc, 0, -1); // clip space point
                 // project clip space to view space (2d to 3d)
                float4 viewPos = mul(_CameraInvProjection, clip);  // still homogenous coordinates (non-singular w)
                viewPos /= abs(viewPos.w) + 1e-6;  // perspective divide
                // view space is a world space with camera at origin, looking down -Z axis

                float3 rayDirWS = normalize(mul(_CameraToWorld, float4(viewPos.xyz, 0)).xyz);  // convert from camera space to world space (can ignore w now)
                float3 rayOriginWS = GetCameraPositionWS();

                Ray returnedRay = CreateRay(rayOriginWS, rayDirWS);

                return returnedRay;
            }

            
            HitInfo FindNextSurface(float3 rayPos, float3 rayDir, float stepSize)
            {
                HitInfo hitInfo; 

                float2 hitBox = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);


                float dstToBox = hitBox.x;
                float dstInsideBox = hitBox.y;

                if (dstInsideBox <= 0.0f) {
                    // Ray does not intersect box, return nothing
                    hitInfo.didHit = false;
                    return hitInfo;
                }

                // // if ray hits the fluid, then continue through until you exit the fluid
                // float3 entryPos = origin + direction * dstToBox;

                float3 direction = normalize(rayDir);

                float dstTraveled = 0.0f;

                float density = 0.0f;

                float3 lastPosInFluid = rayPos;

                bool hasEnteredFluid = false;

                float dstToTest = dstInsideBox - 0.02f;
                    // Sample initial position

                float threshold = 0.1f; // adjustable based on fluid definition

                float3 lastPos = rayPos;
                float lastDensity = SampleDensity(lastPos);

                
                dstTraveled += dstToBox;
                rayPos += direction * dstToBox;

                bool alreadyInFluid = IsInsideFluid(rayPos);

                while (dstTraveled < dstInsideBox - 0.02f)
                {
                    float3 currentPos = lastPos + direction * stepSize;
                    float currentDensity = SampleDensity(currentPos);

                    bool crossedIntoFluid = (!alreadyInFluid && lastDensity < threshold && currentDensity >= threshold);
                    bool crossedOutOfFluid = (alreadyInFluid && lastDensity > threshold && currentDensity <= threshold);

                    if (crossedIntoFluid || crossedOutOfFluid)
                    {
                        float t = (threshold - lastDensity) / (currentDensity - lastDensity);
                        float3 hitPos = lerp(lastPos, currentPos, t);

                        hitInfo.didHit = true;
                        hitInfo.hitPoint = hitPos;
                        hitInfo.normal = CalculateNormal(hitPos);
                        hitInfo.densityAlongRay = density;

                        hitInfo.isInsideFluid = !alreadyInFluid; // if we *entered*, we're now inside

                        return hitInfo;
                    }

                    // Accumulate total density along ray — optional
                    density += currentDensity * stepSize * _DensityMultiplier;

                    dstTraveled += stepSize;
                    lastPos = currentPos;
                    lastDensity = currentDensity;
                }

                // if you got here, no boundary was hit
                return hitInfo;
            }

            // Get light from environment
            float3 LightEnvironment(float3 rayPos, float3 rayDir)
            {
                return float3(1, 1, 1); // Placeholder for light color
            }

            // RAYMARCHING
            float3 Raymarch(Ray ray) // takes in the uv ray from a pixel
            {
                float3 origin = ray.origin;
                float3 direction = ray.direction;

                // Calculate hit info
                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, ray.origin, ray.direction);
                float dstToBox = hit.x;
                float dstInsideBox = hit.y;

                if (dstInsideBox == 0.0f) {
                    return -1.0f;
                }

                // Prepare for marching
                float3 entryPos = origin + direction * dstToBox;

                float dstTraveled = 0.0f;

                float3 rayPos = entryPos;

                Light mainLight = GetMainLight();

                float3 result = float3(0, 0, 0);

                float totalDensity = 0.0;
                float3 lightDir = normalize(mainLight.direction);

                // while ray is still inside 
                while (dstTraveled < dstInsideBox)
                {
                    rayPos = entryPos + direction * dstTraveled;
                    dstTraveled += _StepSize;

                    // lighting calculations per step
                    float densityAlongStep = SampleDensity(rayPos) * _StepSize * _DensityMultiplier;
                    totalDensity += densityAlongStep;


                    float3 beerDecayFactor = exp(-totalDensity * _ScatteringCoefficients);   // note: scattering coefficient = scatter more of that color

                    // factor in lighting calculations based on the position
                    float densityAlongLightDir = CalculateDensityAlongRay(rayPos, lightDir, _LightStepSize);
                    float3 lightBeerDecayFactor = exp(-densityAlongLightDir * _ScatteringCoefficients); // decay factor for light (more density = more decay)

                    float3 lightAlongStep = lightBeerDecayFactor * densityAlongStep * _ScatteringCoefficients;

                    result += beerDecayFactor * lightAlongStep; 
                }
                return result;
                /// new idea: 
                // initialize a light color that you will grab
                // 1. hit a surface, if no hit then break;
                // 2. calculate the density along the ray and multiply that onto the transmittance
                //  2. calculate normal, determine if inside fluid, find indices of refraction, calculate reflection and refraction
                //     directions. Also calculate the reflect and refraction strengths
                // 3. set ray to follow what you calculated 
                // 4. multiply transmittance by either refract or reflection strength
                // 5. approximate light from environment, add to result
                // after loop:
                // 6. after you exit the loop, the ray will point in a certain direction. this is the main bit of light that the ray will consume
            }


            // rendering to screen
            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                
                float4 worldColor = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);

                worldColor = float4(0,0,0,0); // Clear color to black, for debugging

                Ray ray = GetRay(input.uv);

                // returns (dstToBox, dstInsideBox)
                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, ray.origin, ray.direction);


                // sample depth texture to get flattened 0-1 depth
                float nonLinearDepthTexture = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // get world linear value from depth texture
                float depthTexture = LinearEyeDepth(nonLinearDepthTexture, _ZBufferParams) * length(ray.direction);
                

                // if ray intersects box and depth texture is less than the distance to the box (box is not obstructed) commit raymarching
                if (hit.y > 0 && depthTexture > hit.x) {
                    float3 raymarch = Raymarch(ray);

                    return raymarch.x < 0 ? worldColor : float4(raymarch, 1); // if raymarch returns -1, return the world color
                }

                // If ray misses box, return the color from the camera opaque texture
                return worldColor;
            }

            ENDHLSL

        }
    }
}
