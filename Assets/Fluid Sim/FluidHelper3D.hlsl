

float2 worldToScreenPos(float4 worldPos, float4x4 projMatrix, float4x4 viewMatrix, float2 screen)
{
    float4x4 vpMatrix = projMatrix * viewMatrix;
    
    float4 clip = mul(vpMatrix, worldPos);
    
    // perspective divide
    float3 ndc = clip.xyz / clip.w;
    
    float2 screenUV = ndc.xy * 0.5 + 0.5;
    float2 screenPos = screenUV * float2(screen.x, screen.y);
    
    return screenPos;
}

float remap01(float t, float oldMin, float oldMax)
{
    return (t - oldMin) * (1.0f / (oldMax - oldMin));
}

//                      Smoothing Kernel calculations
/* 
Smoothing kernel equation extracted from 
Particle-Based Fluid Simulation for Interactive Applications by Matthias Muller, David Charypar and Markus Gross

 example Poly6 smoothing kernel used in soSPH (Smoothed Particle Hydrodynamics):
 W_poly6(r, h) = (315 / (64 * pi * h^9)) * (h^2 - r^2)^3, for 0 <= r <= h
              = 0, otherwise

 where:
 - r is the distance to the particle (r = ||r_i - r_j||)
 - h is the smoothing length (defines the kernel support radius)
 - The kernel smoothly goes to 0 at r = h and is normalized over its support
*/


// 3d conversion: done
float SmoothingKernelPoly6(float dst, float radius)
{
    if (dst < radius)
    {
        float scale = 315 / (64 * 3.14159265 * pow(abs(radius), 9));
        float v = radius * radius - dst * dst;
        return v * v * v * scale;
    }
    return 0;
}


// 3d conversion: done
//Integrate[(h-r)^2 r^2 Sin[theta], {r, 0, h}, {theta, 0, pi}, {phi, 0, 2*pi}]
float SpikyKernelPow2(float dst, float radius)
{
    if (dst < radius)
    {
        float scale = 15 / (2 * 3.14159265 * pow(radius, 5));
        float v = radius - dst;
        return v * v * scale;
    }
    return 0;
}


// 3d conversion: done
float SpikyKernelPow3(float dst, float radius)
{
    if (dst < radius)
    {
        float scale = 15 / (3.14159265 * pow(radius, 6));
        float v = radius - dst;
        return v * v * v * scale;
    }
    return 0;
}


// 3d conversion: done
float DerivativeSpikyPow2(float dst, float radius)
{
    if (dst <= radius)
    {
        float scale = 15 / (pow(radius, 5) * 3.14159265);
        float v = radius - dst;
        return -v * scale;
    }
    return 0;
}

// 3d conversion: done
float DerivativeSpikyPow3(float dst, float radius)
{
    if (dst <= radius)
    {
        float scale = 45 / (pow(radius, 6) * 3.14159265);
        float v = radius - dst;
        return -v * v * scale;
    }
    return 0;
}

float GetParticleInfluence(float dst, float radius)
{
    return SmoothingKernelPoly6(dst, radius);
    
    //float h = abs(radius);
    
    ////float smoothFunctionVolume = 315.0f / (256.0f * pow(3.14159265, 8) * h);
    
    //// this smooth function volume is calculated with a polar coordinate double integral over the circle formed by h around the particle 
    //float smoothFunctionVolume = 3.14159265 * pow(h, 8) / 4.0f;
    
    //if (0 <= dst && dst <= h)
    //{
    //    float h2 = h * h;
    //    float r2 = dst * dst;
        
    //    float value = h2 - r2;

    //    return value * value * value / smoothFunctionVolume;
    //}
    //else
    //{
    //    return 0.0f;
    //}
}

float GetParticleInfluenceSharp(float r, float h)
{
    return SpikyKernelPow2(r, h);
    
    //h = abs(h);
    
    //// this smooth function volume is calculated with a polar coordinate double integral over the circle formed by h around the particle 
    //float smoothFunctionVolume = 3.14159265 * pow(h, 4) / 6.0f;
    
    //if (0 <= r && r <= h)
    //{
    //    float value = h - r;
        
    //    //float factor = 315.0 / (64.0 * 3.14159265 * pow(abs(h), 9.0f));
    //    return value * value / smoothFunctionVolume;
    //}
    //else
    //{
    //    return 0.0f;
    //}
}

float GetParticleInfluenceSlopeSharp(float r, float h)
{
    return DerivativeSpikyPow2(r, h);
    
    //if (r >= h)
    //    return 0.0f;
    
    //float factor = -12 / (3.14159265 * pow(h, 4));

    //float f = (h - r);
    
    //float slope = factor * f;

    //return slope;
}

float GetParticleInfluenceSharpV3(float r, float h)
{
    return SpikyKernelPow3(r, h);
    
    //h = abs(h);
    
    //float smoothFunctionVolume = 3.14159265 * pow(h, 7) / 21.0f;
    
    //if (0 <= r && r <= h)
    //{
    //    float value = h - r;
        
    //    //float factor = 315.0 / (64.0 * 3.14159265 * pow(abs(h), 9.0f));
    //    return value * value * value * value * value / smoothFunctionVolume;
    //}
    //else
    //{
    //    return 0.0f;
    //}
}

float GetParticleInfluenceSlopeSharpV3(float r, float h)
{
    return DerivativeSpikyPow3(r, h);
    
    //h = abs(h);
    
    //if (r >= h)
    //    return 0.0f;
    
    //float factor = -(5 * 21) / (3.14159265 * pow(h, 7));

    //float f = (h - r);
    
    //float slope = factor * f * f * f * f;

    //return slope;
}


//                OPTIMIZATION

// hash a cell coordinate to a hashed value (by multiplying by a large prime number), 
// which will wrap around based on 
static const int3 offsets3D[27] =
{
    int3(-1, -1, -1),
	int3(-1, -1, 0),
	int3(-1, -1, 1),
	int3(-1, 0, -1),
	int3(-1, 0, 0),
	int3(-1, 0, 1),
	int3(-1, 1, -1),
	int3(-1, 1, 0),
	int3(-1, 1, 1),
	int3(0, -1, -1),
	int3(0, -1, 0),
	int3(0, -1, 1),
	int3(0, 0, -1),
	int3(0, 0, 0),
	int3(0, 0, 1),
	int3(0, 1, -1),
	int3(0, 1, 0),
	int3(0, 1, 1),
	int3(1, -1, -1),
	int3(1, -1, 0),
	int3(1, -1, 1),
	int3(1, 0, -1),
	int3(1, 0, 0),
	int3(1, 0, 1),
	int3(1, 1, -1),
	int3(1, 1, 0),
	int3(1, 1, 1)
};

struct Particle
{
    float3 position;
    float3 velocity;
    float radius;
    
    float3 predictedPosition;
    
    float density;
    float nearDensity;
};

struct Entry
{
    uint particleIndex;
    uint hash;
    uint cellKey;
};

uint HashCell(int cellX, int cellY, int cellZ)
{
    const int PRIME1 = 15823;
    const int PRIME2 = 14999;
    const int PRIME3 = 9737333;
    
    const int PRIME4 = 31;
    
    int positiveX = (uint) (cellX + PRIME4);
    int positiveY = (uint) (cellY + PRIME4);
    int positiveZ = (uint) (cellZ + PRIME4);

    
    int hash = positiveX * PRIME1 + positiveY * PRIME2 + positiveZ * PRIME3;
    //hash = hash & 0x7fffffff; // force non-negative (mask sign bit)

    return (uint) hash;
}

uint KeyFromHash(uint hash, uint tableSize)
{
    return hash % (tableSize);
}


int3 PositionToCellCoord(float3 position, float smoothingRadius, float3 boundsCenter, float3 boundsExtents) 
{
    float3 offset = float3(boundsCenter.x - boundsExtents.x, boundsCenter.y - boundsExtents.y, boundsCenter.z - boundsExtents.z);
    return (int3) floor((position - offset) / smoothingRadius);
}

float3 PseudoRandomDir3D(int seed)
{
    float x = sin(seed * 12.9898);
    float y = cos(seed * 78.233);
    float z = sin(seed * 37.719);
    
    // Generate two angles from hashed values
    float theta = frac(x + y) * 6.2831853; // azimuthal angle [0, 2pi]
    float phi = acos(frac(z) * 2.0 - 1.0); // polar angle [0, pi]

    // Convert spherical to cartesian
    float sinPhi = sin(phi);
    return float3(
        cos(theta) * sinPhi,
        sin(theta) * sinPhi,
        cos(phi)
    );
}
