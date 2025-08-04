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

            float _IndexOfRefraction;

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

            uint NextRandom(inout uint state)
            {
                state = state * 747796405 + 2891336453;
                uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
                result = (result >> 22) ^ result;
                return result;
            }

            float RandomValue(inout uint state)
            {
                return NextRandom(state) / 4294967295.0; // 2^32 - 1
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
                //bool isInsideFluid; // true if ray is entering fluid, false if ray is exiting fluid (regarding boundary)

                float3 hitPoint;
                float3 normal;
                float densityAlongRay;
            };
                        
            struct SurfaceInfo
            {
                float3 pos;
                float3 normal;
                float densityAlongRay;
                bool foundSurface;
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
            // float SampleDensity(float3 pos)
            // {

            //     // convert world position to [0-1] UVW range
            //     float3 uvw = (pos - _BoxBoundsMin) / (_BoxBoundsMax - _BoxBoundsMin);

            //     // if uvw is epsilon away from 0 or 1, then return -volumeValueOffset (-150, large negative) to cut out fuzzy edges
            //     const float epsilon = 0.0001f;
            //     bool isEdge = any(uvw >= 1 - epsilon || uvw <= epsilon);
            //     if (isEdge) return -volumeValueOffset;

            //     // sample the 3d texture by the [0-1] UVW coordinate range
            //     return _DensityMap.SampleLevel(sampler_DensityMap, uvw, 0).r;
            // }

            float SampleDensity(float3 pos)
            {
                float3 boundsSize = _BoxBoundsMax - _BoxBoundsMin;

                float3 uvw = (pos + boundsSize * 0.5) / boundsSize;

                const float epsilon = 0.0001;
                bool isEdge = any(uvw >= 1 - epsilon || uvw <= epsilon);
                if (isEdge) return -volumeValueOffset;

                return _DensityMap.SampleLevel(sampler_DensityMap, uvw, 0).r - volumeValueOffset;
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
            
            float CalculateDensityAlongRay(float3 origin, float3 direction, float stepSize)
            {
                float density = 0.0;

                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, origin, direction);

                float dstTraveled = 0.0f;

                const float nudge = stepSize * 0.5;
                const float3 entryPos = origin + direction * (hit.x);
                const float dstInsideBox = hit.y - (nudge + 0.01f);

                if (dstInsideBox == 0.0f) {
                    // Ray does not intersect box, return 0 density
                    return 0.0f;
                }

                float3 rayPos = entryPos;

                // while ray is still inside 
                while (dstTraveled < dstInsideBox)
                {
                    rayPos = entryPos + direction * dstTraveled;
                    dstTraveled += stepSize;
                    
                    float densityAlongStep = SampleDensity(rayPos) * stepSize * _DensityMultiplier;

                    if (densityAlongStep <= 0.0f)
                    {
                        continue;
                    }

                    density += densityAlongStep;
                }

                return density;
            }
            // -- // -- //


            // Reconstruct ray direction from UV
            Ray GetRay(float2 uv) {
                
                // construct ray per pixel
                const float2 ndc = uv * 2.0 - 1.0; // 0..1 UV -> -1..1 NDC

                const float4 clip = float4(ndc, 0, -1); // clip space point
                 // project clip space to view space (2d to 3d)
                float4 viewPos = mul(_CameraInvProjection, clip);  // still homogenous coordinates (non-singular w)
                viewPos /= abs(viewPos.w) + 1e-6;  // perspective divide
                // view space is a world space with camera at origin, looking down -Z axis

                const float3 rayDirWS = normalize(mul(_CameraToWorld, float4(viewPos.xyz, 0)).xyz);  // convert from camera space to world space (can ignore w now)
                const float3 rayOriginWS = GetCameraPositionWS();

                return CreateRay(rayOriginWS, rayDirWS);
            }

            HitInfo RayBox(float3 rayPos, float3 rayDir)
            {
                HitInfo hitInfo = (HitInfo)0;
                float2 hitBox = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);
                hitInfo.didHit = hitBox.y > 0;
                if (!hitInfo.didHit) return hitInfo;
                // calculate the intersection point
                hitInfo.hitPoint = rayPos + rayDir * hitBox.x;
                // calculate the normal at the intersection point
                hitInfo.normal = CalculateNormal(hitInfo.hitPoint);
                // calculate density along ray
                // check if inside fluid
                // hitInfo.distance = hitBox.x;
                return hitInfo;
            }

            HitInfo FindNextSurface(float3 origin, float3 rayDir, bool travellingThroughFluid, float maxDst)
            {
                HitInfo info = (HitInfo)0;
                if (dot(rayDir, rayDir) < 0.5) return info;

                float2 boundsDstInfo = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, origin, rayDir);

                bool hasExittedFluid = !IsInsideFluid(origin);
                origin = origin + rayDir * (boundsDstInfo.x);

                const float stepSize = _StepSize;
                const float densityMulti = _DensityMultiplier;

                bool hasEnteredFluid = false;
                float3 lastPosInFluid = origin;

                const float dstToTest = boundsDstInfo.y - (0.01f) * 2;

                for (float dst = 0; dst < dstToTest; dst += stepSize)
                {
                    bool isLastStep = dst + stepSize >= dstToTest; // at border of testing
                    float3 samplePos = origin + rayDir * dst;
                    float densityAlongStep = SampleDensity(samplePos) * densityMulti * stepSize;

                    bool insideFluid = densityAlongStep > 0; // we are now inside the fluid
                    if (insideFluid)
                    {
                        hasEnteredFluid = true;
                        lastPosInFluid = samplePos;

                        if (dst <= maxDst)
                        {
                            info.densityAlongRay += densityAlongStep; // add onto the density as we go!
                        }
                    }

                    if (!insideFluid) hasExittedFluid = true;

                    // how can found be true?
                    bool found;
                    if (!travellingThroughFluid) found = insideFluid && hasExittedFluid;
                    else found = hasEnteredFluid && (!insideFluid || isLastStep);

                    // if we are trying to find the next fluid entry, i.e. we are in air,
                    // found = true only if we are inside the fluid AND we have exitted the fluid once
                    // so basically if we start inside fluid to begin with, that doesn't count as going through the fluid!
                    // hasExittedFluid toggles to true only when we are no longer inside fluid

                    // if we are traveling through fluid, then found is true when we have entered fluid once 
                    // AND we are not inside the fluid anymore OR it's the last step, meaning we have gone to the absolute border of the bounds

                    // essentially this system makes sure we break at the right time no matter where we start from
                    // if we are travelling through air, then we exit right when we enter fluid
                    // if we are travelling through fluid, then we exit right when we enter air

                    // this seems redundant but we always start slightly inside the water while traversing in air, and slightly inside
                    // the air while traversing in water. we have to leave a bit of leeway

                    if (found)
                    {
                        info.didHit = true;
                        info.hitPoint = lastPosInFluid;

                        info.normal = CalculateNormal(lastPosInFluid);
                        if (dot(info.normal, rayDir) > 0) info.normal = -info.normal;

                        break;
                    }
                }

                return info;
            }

            // ENVIRONMENT //
            float3 DirToSun() 
            {
                Light mainLight = GetMainLight();
                return -mainLight.direction;
            }

            float3 SampleSky(float3 dir)
            {
                const float3 colGround   = float3(0.35, 0.3, 0.35) * 0.53;
                const float3 colSkyHorizon  = float3(1, 1, 1);
                const float3 colSkyZenith = float3(0.08, 0.37, 0.73);

                float sun = pow(max(0, dot(dir, DirToSun())), 500) * 1;
                float skyGradientT = pow(smoothstep(0, 0.4, dir.y), 0.35);
                float groundToSkyT = smoothstep(-0.01, 0, dir.y);
                float3 skyGradient = lerp(colSkyHorizon, colSkyZenith, skyGradientT);

                return lerp(colGround, skyGradient, groundToSkyT) + sun * (groundToSkyT >= 1);
            }


            // Get light from environment
            float3 LightEnvironment(float3 rayPos, float3 rayDir)
            {
                return SampleSky(rayDir); // Placeholder for light color
            }

            // -- // -- //

            // RAYMARCHING
            // float3 Raymarch(Ray ray)
            // {
            //     //uint rngState = (uint)(uv.x * 1243 + uv.y * 96456);

            //     float3 rayDir = ray.direction;
            //     float3 rayPos = ray.origin;
            //     bool travellingThroughFluid = IsInsideFluid(rayPos);

            //     float3 transmittance = 1;
            //     float3 light = 0;



            //     for (int i = 0; i < _NumRefractions; i++)
            //     {
            //         float densityStepSize = _LightStepSize * (i + 1); // increase step size with each iteration
            //         bool searchForNextFluidEntryPoint = !travellingThroughFluid;

            //         float2 cubeHit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);

            //         HitInfo surfaceInfo = FindNextSurface(rayPos, rayDir, searchForNextFluidEntryPoint, cubeHit.y);
            //         bool useCubeHit = cubeHit.y >= 0 && cubeHit.x < length(surfaceInfo.hitPoint - rayPos);

            //         if (!surfaceInfo.didHit) break;

            //         transmittance *= exp(-surfaceInfo.densityAlongRay * _ScatteringCoefficients);

            //         // // Hit test cube
            //         // if (useCubeHit)
            //         // {
            //         //     if (travellingThroughFluid)
            //         //     {
            //         //         transmittance *= Transmittance(CalculateDensityAlongRay(cubeHit.hitPoint, cubeHit.normal, densityStepSize));
            //         //     }
            //         //     light += Light(rayPos, rayDir) * transmittance;
            //         //     transmittance = 0;
            //         //     break;
            //         // }

            //         // // If light hits the floor it will be scattered in all directions (in hemisphere)
            //         // // Not sure how to handle this in real-time, so just break out of loop here
            //         // if (surfaceInfo.pos.y < -boundsSize.y / 2 + 0.05)
            //         // {
            //         //     break;
            //         // }

            //         float3 normal = CalculateNormal(surfaceInfo.hitPoint);
            //         if (dot(normal, rayDir) > 0) normal = -normal;

            //         // Indicies of refraction
            //         float iorA = travellingThroughFluid ? 1.33f : 1;
            //         float iorB = travellingThroughFluid ? 1 : 1.33f;

            //         // Calculate reflection and refraction, and choose which path to follow
            //         LightResponse lightResponse = CalculateRefractionAndReflection(rayDir, normal, iorA, iorB);
            //         float densityAlongRefractRay = CalculateDensityAlongRay(surfaceInfo.hitPoint, lightResponse.refractDir, densityStepSize);
            //         float densityAlongReflectRay = CalculateDensityAlongRay(surfaceInfo.hitPoint, lightResponse.reflectDir, densityStepSize);
            //         bool traceRefractedRay = densityAlongRefractRay * lightResponse.refractStrength > densityAlongReflectRay * lightResponse.reflectStrength;
            //         travellingThroughFluid = traceRefractedRay != travellingThroughFluid;

            //         // Approximate less interesting path
            //         if (traceRefractedRay) light += LightEnvironment(surfaceInfo.hitPoint, lightResponse.reflectDir) * transmittance * exp(-densityAlongReflectRay * _ScatteringCoefficients) * lightResponse.reflectStrength;
            //         else light += LightEnvironment(surfaceInfo.hitPoint, lightResponse.refractDir) * transmittance * exp(-densityAlongRefractRay * _ScatteringCoefficients) * lightResponse.refractStrength;

            //         // Set up ray for more interesting path
            //         rayPos = surfaceInfo.hitPoint;
            //         rayDir = traceRefractedRay ? lightResponse.refractDir : lightResponse.reflectDir;
            //         transmittance *= (traceRefractedRay ? lightResponse.refractStrength : lightResponse.reflectStrength);
            //     }

            //     // Approximate remaining path
            //     float densityRemainder = CalculateDensityAlongRay(rayPos, rayDir, _LightStepSize);
            //     light += LightEnvironment(rayPos, rayDir) * transmittance * exp(-densityRemainder * _ScatteringCoefficients);

            //     return 1 - light;
            // }
            /// idea: 
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
            
            float3 Raymarch(Ray ray) // takes in the uv ray from a pixel
            {
                float3 lightColor = float3(0, 0, 0); // Initialize light color

                // initialize transmittance to 1.0
                float3 transmittance = 1;

                float3 rayPos = ray.origin;
                float3 rayDir = ray.direction;

                //float3 origin = ray.origin + ray.direction * dstToBox; // calculate the origin of the ray at the intersection point
                bool travellingThroughFluid = IsInsideFluid(rayPos);

                const float3 scatterCoeff = _ScatteringCoefficients;


                // within a loop of refractions,
                for (int i = 0; i < _NumRefractions; i++)
                {
                    float densityStepSize = _LightStepSize * (i + 1); // increase step size with each iteration as each iteration becomes less important

                    // find the next surface hit
                    float2 hitBox = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);

                    float dstToBox = hitBox.x;
                    float dstInsideBox = hitBox.y;

                    HitInfo hitInfo = FindNextSurface(rayPos, rayDir, travellingThroughFluid, dstInsideBox);

                    if (!hitInfo.didHit) {
                        // if no hit, then break out of the loop
                        break;
                    }

                    // calculate the density along the ray and multiply
                    transmittance *= exp(-hitInfo.densityAlongRay * scatterCoeff); // todo: also multiply by scattering coeff

                    float iorA = travellingThroughFluid ? _IndexOfRefraction : 1.0f; // if inside fluid, use fluid IOR, otherwise use air IOR
                    float iorB = 1.0 + _IndexOfRefraction - iorA; // if inside fluid, use air IOR, otherwise use fluid IOR

                    // calculate reflection and refraction directions
                    LightResponse lightResponse = CalculateRefractionAndReflection(rayDir, hitInfo.normal, iorA, iorB);

                    float densityRefract = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.refractDir, densityStepSize);
                    float densityReflect = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.reflectDir, densityStepSize);

                    bool isRefracting = (densityRefract * lightResponse.refractStrength) > (densityReflect * lightResponse.reflectStrength); 

                    // cheeky way to optimize if statement (if refracting, primaryDir = refractDir)
                    float3 primaryDir = lerp(lightResponse.reflectDir, lightResponse.refractDir, isRefracting);
                    float3 secondaryDir = lerp(lightResponse.refractDir, lightResponse.reflectDir, isRefracting);

                    float secondaryStrength = lerp(lightResponse.refractStrength, lightResponse.reflectStrength, isRefracting);
                    float secondaryDensity  = lerp(densityRefract, densityReflect, !isRefracting);

                    float3 secondaryFactor = secondaryStrength * exp(-secondaryDensity * scatterCoeff);
                    
                    // approximate less interesting path?
                    lightColor += LightEnvironment(hitInfo.hitPoint, secondaryDir) * transmittance * secondaryFactor;

                    rayPos = hitInfo.hitPoint;
                    rayDir = primaryDir;

                    transmittance *= (isRefracting ? lightResponse.refractStrength : lightResponse.reflectStrength); // multiply transmittance by the strength of the refraction or reflection
                    
                    // if refracting and travellingThroughFluid, then we are no longer travellingThroughFluid
                    // if refracting and not travellingThroughFluid, then we are now travellingThroughFluid
                    // if reflecting and travellingThroughFluid, then we are now travellingThroughFluid
                    // if reflecting and not travellingThroughFluid, then we are still not travellingThroughFluid
                    travellingThroughFluid = isRefracting != travellingThroughFluid;
                }

                // Add light from the environment based on the final ray direction
                const float densityRemainder = CalculateDensityAlongRay(rayPos, rayDir, _LightStepSize);

                lightColor += LightEnvironment(rayPos, rayDir) * transmittance * exp(-densityRemainder * scatterCoeff); 

                return lightColor; // Return the final light color
            }


            // rendering to screen
            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                
                float4 worldColor = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);

                Ray ray = GetRay(input.uv);
                worldColor = float4(LightEnvironment(ray.origin, ray.direction),0); // Clear color to black, for debugging

                //worldColor = 0;
                // returns (dstToBox, dstInsideBox)
                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, ray.origin, ray.direction);

                // sample depth texture to get flattened 0-1 depth
                float nonLinearDepthTexture = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // get world linear value from depth texture
                float depthTexture = LinearEyeDepth(nonLinearDepthTexture, _ZBufferParams) * length(ray.direction);

                // if ray intersects box and depth texture is less than the distance to the box (box is not obstructed) commit raymarching
                if (hit.y > 0) {
                    //float3 raymarch = Raymarch(input.uv, ray, _StepSize);
                    float3 raymarch = Raymarch(ray);
                    return float4(raymarch, 1); // if raymarch returns -1, return the world color
                }

                // If ray misses box, return the color from the camera opaque texture
                return worldColor;
            }

            ENDHLSL

        }
    }
}
