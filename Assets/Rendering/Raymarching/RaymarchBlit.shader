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

                // Fullscreen triangle (usually it goes from -1 to 1)
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

            // test cube
            float3 _TestCubeBoundsMin;
            float3 _TestCubeBoundsMax;

            float4x4 _TestCubeLocalToWorld;
            float4x4 _TestCubeWorldToLocal;

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

            struct CubeInfo
            {
                bool didHit;
                bool isInside;
                float dst;
                float3 hitPoint;
                float3 normal;
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

                float3 uvw = (pos - _BoxBoundsMin) / (_BoxBoundsMax - _BoxBoundsMin);

                const float epsilon = 0.0001;
                bool isEdge = any(uvw >= 1 - epsilon || uvw <= epsilon);
                if (isEdge) return -volumeValueOffset;

                return _DensityMap.SampleLevel(sampler_DensityMap, uvw, 0).r - volumeValueOffset;
            }
            
            float3 Transmittance(float thickness)
            {
                return exp(-thickness * _ScatteringCoefficients);
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

                float3 uvw = (pos - _BoxBoundsMin) / (_BoxBoundsMax - _BoxBoundsMin);

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
                bool withinBox = (boundsDstInfo.x <= 0 && boundsDstInfo.y > 0);

                return withinBox && SampleDensity(pos) > 0;
            }

            // Calculate the proportion of light that is reflected at the boundary between two media (via the fresnel equations)
            float CalculateReflectance(float3 inDir, float3 normal, float iorA, float iorB)
            {
                float refractRatio = iorA / iorB;
                float cosAngleIn = -dot(inDir, normal);
                float sinSqrAngleOfRefraction = refractRatio * refractRatio * (1 - cosAngleIn * cosAngleIn);

                if (sinSqrAngleOfRefraction >= 1) return 1; // Ray is fully reflected, no refraction occurs

                float cosAngleOfRefraction = sqrt(1 - sinSqrAngleOfRefraction);

                //// // Fresnel equations for reflectance I don't really understand
                // Perpendicular polarization
                float rPerpendicular = (iorA * cosAngleIn - iorB * cosAngleOfRefraction) / (iorA * cosAngleIn + iorB * cosAngleOfRefraction);
                rPerpendicular *= rPerpendicular;
                // Parallel polarization
                float rParallel = (iorB * cosAngleIn - iorA * cosAngleOfRefraction) / (iorB * cosAngleIn + iorA * cosAngleOfRefraction);
                rParallel *= rParallel;

                // Return the average of the perpendicular and parallel polarizations
                return (rPerpendicular + rParallel) / 2;
            }

            // n1cos(theta1) = n2cos(theta2)
            float3 Refract(float3 inDir, float3 normal, float iorA, float iorB)
            {
                float refractRatio = iorA / iorB;
                float cosAngleIn = -dot(inDir, normal);  // theta1
                float sinSqrAngleIn = (1 - cosAngleIn * cosAngleIn);
                float sinSqrAngleOfRefraction = refractRatio * refractRatio * (sinSqrAngleIn);

                // sin^2(theta2) can possibly be greater than 1, which means total internal reflection
                if (sinSqrAngleOfRefraction > 1) return 0; // Ray is fully reflected, no refraction occurs

                float cosAngleOfRefraction = sqrt(1 - sinSqrAngleOfRefraction);

                float3 refractDir = refractRatio * inDir + (refractRatio * cosAngleIn - cosAngleOfRefraction) * normal;
                return refractDir;
            }

            float3 Reflect(float3 inDir, float3 normal)
            {
                return inDir - 2 * dot(inDir, normal) * normal;
            }


            LightResponse CalculateReflectionAndRefraction(float3 inDir, float3 normal, float iorA, float iorB)
            {
                LightResponse result;

                result.reflectStrength = CalculateReflectance(inDir, normal, iorA, iorB);
                result.refractStrength = 1 - result.reflectStrength;

                result.reflectDir = Reflect(inDir, normal);
                result.refractDir = Refract(inDir, normal, iorA, iorB);

                return result;
            }

            // Test intersection of ray with unit box centered at origin
            CubeInfo RayUnitBox(float3 pos, float3 dir)
            {
                float3 minBox = -0.5f;
                float3 maxBox = 0.5f;
                float3 invDir = 1 / dir;

                // Thanks to https://tavianator.com/2011/ray_box.html
                float3 tMin = (minBox - pos) * invDir;
                float3 tMax = (maxBox - pos) * invDir;
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);
                float tNear = max(max(t1.x, t1.y), t1.z);
                float tFar = min(min(t2.x, t2.y), t2.z);

                // Set hit info
                CubeInfo cubeInfo = (CubeInfo)0;
                cubeInfo.dst = 1.#INF;
                cubeInfo.didHit = tFar >= tNear && tFar > 0;
                cubeInfo.isInside = tFar > tNear && tNear <= 0;

                if (cubeInfo.didHit)
                {
                    float hitDst = cubeInfo.isInside ? tFar : tNear;
                    float3 hitPos = pos + dir * hitDst;

                    cubeInfo.dst = hitDst;
                    cubeInfo.hitPoint = hitPos;

                    // Calculate normal
                    float3 o = (1 - abs(hitPos));
                    float3 absNormal = (o.x < o.y && o.x < o.z) ? float3(1, 0, 0) : (o.y < o.z) ? float3(0, 1, 0) : float3(0, 0, 1);
                    cubeInfo.normal = absNormal * sign(hitPos) * (cubeInfo.isInside ? -1 : 1);
                }

                return cubeInfo;
            }

            CubeInfo RayCubeInfoBox(float3 rayPos, float3 rayDir, float4x4 localToWorld, float4x4 worldToLocal)
            {
                float3 posLocal = mul(worldToLocal, float4(rayPos, 1));
                float3 dirLocal = mul(worldToLocal, float4(rayDir, 0));
                CubeInfo cubeInfo = RayUnitBox(posLocal, dirLocal);
                cubeInfo.normal = normalize(mul(localToWorld, float4(cubeInfo.normal, 0)));
                cubeInfo.hitPoint = mul(localToWorld, float4(cubeInfo.hitPoint, 1));
                if (cubeInfo.didHit) cubeInfo.dst = length(cubeInfo.hitPoint - rayPos);
                return cubeInfo;
            }

            
            float CalculateDensityAlongRay(float3 rayPos, float3 rayDir, float stepSize)
            {
                // Test for non-normalize ray and return 0 in that case.
                // This happens when refract direction is calculated, but ray is totally reflected
                if (dot(rayDir, rayDir) < 0.9) return 0;

                float2 boundsDstInfo = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);
                float dstToBounds = boundsDstInfo.x;
                float dstThroughBounds = boundsDstInfo.y;

                if (dstThroughBounds <= 0) return 0;

                float dstTravelled = 0;
                float opticalDepth = 0;
                float nudge = stepSize * 0.5;

                float3 entryPos = rayPos + rayDir * (dstToBounds + nudge);

                dstThroughBounds -= (nudge + 0.01f); //(tiny nudge)

                while (dstTravelled < dstThroughBounds)
                {
                    rayPos = entryPos + rayDir * dstTravelled;

                    float density = SampleDensity(rayPos) * _DensityMultiplier * stepSize;
                    if (density > 0)
                    {
                        opticalDepth += density;
                    }
                    dstTravelled += stepSize;
                }

                return opticalDepth;
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

            HitInfo FindNextSurface(float3 origin, float3 rayDir, bool searchForNextFluidEntryPoint, float maxDst, uint rngState, float rngWeight)
            {
                HitInfo info = (HitInfo)0;
                if (dot(rayDir, rayDir) < 0.5) return info;

                float2 boundsDstInfo = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, origin, rayDir);

                float r = (RandomValue(rngState) - 0.5) * _StepSize * 0.4 * 1;


                bool hasExittedFluid = !IsInsideFluid(origin);
                origin = origin + rayDir * (boundsDstInfo.x + r);

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
                    if (searchForNextFluidEntryPoint) found = insideFluid && hasExittedFluid;
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
                return mainLight.direction;
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


            float3 CheckerColor()
            {

            }

            float3 TestCubeColor(CubeInfo cubeInfo, float3 dirToSun)
            {
                // color of test cube
                float3 cubeNormal = cubeInfo.normal;
                return saturate(dot(cubeNormal, dirToSun) * 0.5f + 0.5f);
            }

            float3 Environment(float3 rayPos, float3 worldDir)
            {
                // --- Floor parameters ---
                const float floorHeight = -5.0;             // y = 0 plane
                const float3 floorColor = float3(0.7, 0.7, 0.9); // dark gray/blueish

                // Ray origin and direction
                float3 rayDir = normalize(worldDir);

                // --- Ray-plane intersection ---
                float3 P0 = float3(0, floorHeight, 0); // origin of plane
                float3 n = float3(0, 1, 0); // normal of plane (directly up)

                // Test Cube
                CubeInfo cubeInfo = RayCubeInfoBox(rayPos, rayDir, _TestCubeLocalToWorld, _TestCubeWorldToLocal);

                float3 dirToSun = DirToSun();

                float4 camPos = mul(_CameraToWorld, float4(0, 0, 0, 1));

                // if (camPos.y < floorHeight)
                // {
                //     if (cubeInfo.didHit && cubeInfo.hitPoint.y < floorHeight)
                //     {
                //         return TestCubeColor();
                //     }
                // }

                bool renderCube = (cubeInfo.hitPoint.y > floorHeight && camPos.y > floorHeight) || 
                    (cubeInfo.hitPoint.y < floorHeight && camPos.y < floorHeight);

                if (cubeInfo.didHit && renderCube)
                {
                    return TestCubeColor(cubeInfo, dirToSun);
                }

                // CALCULATE INTERSECTION
                // rayOrigin + t * rayDir = P (point on plane)
                // dot((P - P0), n) = 0
                // dot (rayOrigin + t * rayDir - P0, n) = 0
                // dot(rayOrigin - P0, n) = -t dot(rayDir, n)
                // t = dot(P0 - rayOrigin, n) / dot(rayDir, n)

                float t = dot(P0 - rayPos, n) / dot(rayDir, n);

                if (t > 0.0 && abs(rayDir.y) > 0.001f) // hit floor in front of camera
                {
                    float3 hitPos = rayPos + t * rayDir;

                    // Simple checker pattern
                    float2 checkerUV = hitPos.xz * 0.5;
                    float checker = abs(fmod(floor(checkerUV.x) + floor(checkerUV.y), 2.0));  // remainder after dividing by 2, alternates 0, 1, diagonally
                    float3 color = lerp(floorColor, floorColor * 1.2, checker);

                    float shadowDensity = CalculateDensityAlongRay(hitPos, dirToSun, _LightStepSize * 2) * 2;
                    float3 shadowMap = exp(-shadowDensity * _ScatteringCoefficients);

                    // TODO: test cube shadow
                    CubeInfo cubeShadowInfo = RayCubeInfoBox(hitPos, dirToSun, _TestCubeLocalToWorld, _TestCubeWorldToLocal);

                    if (cubeShadowInfo.didHit)
                    {
                        shadowMap *= 0.25f;
                    }

                    if (camPos.y < floorHeight && dirToSun.y > 0.0f)
                    {
                        shadowMap = 1.0f;
                    }
                    
                    return color * shadowMap;
                }

                // --- Sky ---
                return SampleSky(worldDir);
            }

            // Get light from environment
            float3 LightEnvironment(float3 rayPos, float3 rayDir)
            {
                return Environment(rayPos, rayDir); // Placeholder for light color
            }

            // -- // -- //

            // RAYMARCHING

            /// idea: 
            // initialize a light color that you will grab
            // 1. hit a surface, if no hit then break;
            // 2. calculate the density along the ray and multiply that onto the transmittance
            //     calculate normal, determine if inside fluid, find indices of refraction, calculate reflection and refraction
            //     directions. Also calculate the reflect and refraction strengths
            // 3. set ray to follow what you calculated 
            // 4. multiply transmittance by either refract or reflection strength
            // 5. approximate light from environment, add to result
            // after loop:
            // 6. after you exit the loop, the ray will point in a certain direction. this is the main bit of light that the ray will consume
            
            float3 Raymarch(Ray ray, float2 uv) // takes in the uv ray from a pixel
            {
                float3 lightColor = float3(0, 0, 0); // Initialize light color

                // initialize transmittance to 1.0
                float3 transmittance = 1;

                float3 rayPos = ray.origin;
                float3 rayDir = ray.direction;

                //float3 origin = ray.origin + ray.direction * dstToBox; // calculate the origin of the ray at the intersection point
                bool travellingThroughFluid = IsInsideFluid(rayPos);

                const float3 scatterCoeff = _ScatteringCoefficients;

                uint rngState = (uint)(uv.x * 1243 + uv.y * 96456);

                // within a loop of refractions,
                for (int i = 0; i < _NumRefractions; i++)
                {
                    // check if hit test cube

                    float densityStepSize = _LightStepSize * (i + 1); // increase step size with each iteration as each iteration becomes less important
                    
                    // find the next surface hit
                    float2 hitBox = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, rayPos, rayDir);

                    bool searchForNextFluidEntryPoint = !travellingThroughFluid;

                                                        
                    // Test Cube
                    CubeInfo cubeInfo = RayCubeInfoBox(rayPos, rayDir, _TestCubeLocalToWorld, _TestCubeWorldToLocal);

                    HitInfo hitInfo = FindNextSurface(rayPos, rayDir, searchForNextFluidEntryPoint, cubeInfo.dst, rngState, i == 0 ? 1 : 0);

                    if (!hitInfo.didHit) {
                        // if no hit, then break out of the loop
                        break;
                    }

                     // calculate the density along the ray and multiply
                    transmittance *= exp(-hitInfo.densityAlongRay * scatterCoeff); // todo: also multiply by scattering coeff

                    bool useCubeHit = cubeInfo.didHit && cubeInfo.dst < length(cubeInfo.hitPoint - rayPos);

                    if (cubeInfo.didHit && cubeInfo.dst < length(hitInfo.hitPoint - rayPos))
                    {
                        if (travellingThroughFluid)
                        {
                            transmittance *= exp(-CalculateDensityAlongRay(cubeInfo.hitPoint, cubeInfo.normal, densityStepSize) * _ScatteringCoefficients);
                        }
                        lightColor += LightEnvironment(rayPos, rayDir) * transmittance;
                        transmittance = 0;
                        break;
                    }

                    // If light hits the floor it will be scattered in all directions (in hemisphere)
                    // Not sure how to handle this in real-time, so just break out of loop here
                    if (hitInfo.hitPoint.y < _BoxBoundsMin.y + 0.05f)
                    {
                        break;
                    }

                    float iorA = travellingThroughFluid ? _IndexOfRefraction : 1.0f;
                    float iorB = travellingThroughFluid ? 1.0f : _IndexOfRefraction;

                    // // calculate reflection and refraction directions
                    // LightResponse lightResponse = CalculateReflectionAndRefraction(rayDir, hitInfo.normal, iorA, iorB);

                    // float densityRefract = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.refractDir, densityStepSize);
                    // float densityReflect = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.reflectDir, densityStepSize);
                    // Calculate reflection and refraction, and choose which path to follow
                    float3 normal = hitInfo.normal;
                    LightResponse lightResponse = CalculateReflectionAndRefraction(rayDir, normal, iorA, iorB);
                    float densityAlongRefractRay = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.refractDir, densityStepSize);
                    float densityAlongReflectRay = CalculateDensityAlongRay(hitInfo.hitPoint, lightResponse.reflectDir, densityStepSize);
                    bool traceRefractedRay = densityAlongRefractRay * lightResponse.refractStrength > densityAlongReflectRay * lightResponse.reflectStrength;
                    travellingThroughFluid = traceRefractedRay != travellingThroughFluid;

                    // Approximate less interesting path
                    if (traceRefractedRay) lightColor += LightEnvironment(hitInfo.hitPoint, lightResponse.reflectDir) * transmittance * Transmittance(densityAlongReflectRay) * lightResponse.reflectStrength;
                    else lightColor += LightEnvironment(hitInfo.hitPoint, lightResponse.refractDir) * transmittance * Transmittance(densityAlongRefractRay) * lightResponse.refractStrength;

                    // Set up ray for more interesting path
                    rayPos = hitInfo.hitPoint;
                    rayDir = traceRefractedRay ? lightResponse.refractDir : lightResponse.reflectDir;
                    transmittance *= (traceRefractedRay ? lightResponse.refractStrength : lightResponse.reflectStrength);
                }

                // Approximate remaining path
                float densityRemainder = CalculateDensityAlongRay(rayPos, rayDir, _LightStepSize);
                lightColor += LightEnvironment(rayPos, rayDir) * transmittance * Transmittance(densityRemainder);

                return lightColor;
            }

            //         bool isRefracting = (densityRefract * lightResponse.refractStrength) > (densityReflect * lightResponse.reflectStrength); 


            //         // cheeky way to optimize if statement (if refracting, primaryDir = refractDir)
            //         float3 primaryDir = lerp(lightResponse.reflectDir, lightResponse.refractDir, isRefracting);
            //         float3 secondaryDir = lerp(lightResponse.refractDir, lightResponse.reflectDir, isRefracting);

            //         float secondaryStrength = lerp(lightResponse.refractStrength, lightResponse.reflectStrength, isRefracting);
            //         float secondaryDensity  = lerp(densityRefract, densityReflect, !isRefracting);

            //         float3 secondaryFactor = secondaryStrength * exp(-secondaryDensity * scatterCoeff);
                    
            //         // approximate less interesting path?
            //         lightColor += LightEnvironment(hitInfo.hitPoint, secondaryDir) * transmittance * secondaryFactor;

            //         rayPos = hitInfo.hitPoint;
            //         rayDir = primaryDir;

            //         transmittance *= (isRefracting ? lightResponse.refractStrength : lightResponse.reflectStrength); // multiply transmittance by the strength of the refraction or reflection
                    
            //         // if refracting and travellingThroughFluid, then we are no longer travellingThroughFluid
            //         // if refracting and not travellingThroughFluid, then we are now travellingThroughFluid
            //         // if reflecting and travellingThroughFluid, then we are now travellingThroughFluid
            //         // if reflecting and not travellingThroughFluid, then we are still not travellingThroughFluid
            //         travellingThroughFluid = isRefracting != travellingThroughFluid;

            //         // if at edge, do not reflect back in?
            //     }

            //     // Add light from the environment based on the final ray direction
            //     float densityRemainder = CalculateDensityAlongRay(rayPos, rayDir, _LightStepSize);
            //     transmittance = max(transmittance, 0.1);

            //     lightColor += LightEnvironment(rayPos, rayDir) * transmittance * exp(-densityRemainder * scatterCoeff); 

            //     return lightColor; // Return the final light color
            // }


            // rendering to screen
            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);


                //float4 worldColor = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);

                Ray ray = GetRay(input.uv);
                float4 worldColor = float4(LightEnvironment(ray.origin, ray.direction),0); // Clear color to black, for debugging

                //worldColor = 0;
                // returns (dstToBox, dstInsideBox)
                float2 hit = rayBoxDst(_BoxBoundsMin, _BoxBoundsMax, ray.origin, ray.direction);

                // sample depth texture to get flattened 0-1 depth
                float nonLinearDepthTexture = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // get world linear value from depth texture
                float depthTexture = LinearEyeDepth(nonLinearDepthTexture, _ZBufferParams) * length(ray.direction);

                float4 camPos = mul(_CameraToWorld, float4(0, 0, 0, 1));

                if (camPos.y < -5.0f)  // TODO: replace with _FloorHeight constant
                {
                    return worldColor;
                }

                float3 raymarch = Raymarch(ray, input.uv);
                return float4(raymarch, 1); // if raymarch returns -1, return the world color

                // If ray misses box, return the color from the camera opaque texture
            }

            ENDHLSL

        }
    }
}
