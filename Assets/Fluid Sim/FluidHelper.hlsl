

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

float GetParticleInfluence(float dst, float radius)
{
    float h = abs(radius);
    
    //float smoothFunctionVolume = 315.0f / (256.0f * pow(3.14159265, 8) * h);
    
    // this smooth function volume is calculated with a polar coordinate double integral over the circle formed by h around the particle 
    float smoothFunctionVolume = 3.14159265 * pow(h, 8) / 4.0f;
    
    if (0 <= dst && dst <= h)
    {
        float h2 = h * h;
        float r2 = dst * dst;
        
        float value = h2 - r2;

        return value * value * value / smoothFunctionVolume;
    }
    else
    {
        return 0.0f;
    }
}

// - 6 rk(h^2 - r^2)^2
float GetParticleInfluenceSlope(float r, float h)
{
    if (r >= h)
        return 0.0f;
    
    float factor = -24 / (3.14159265 * pow(h, 8));

    float f = (h * h - r * r);
    
    float slope = factor * r * f * f;

    return slope;
}

float GetParticleInfluenceSharp(float r, float h)
{
    h = abs(h);
    
    // this smooth function volume is calculated with a polar coordinate double integral over the circle formed by h around the particle 
    float smoothFunctionVolume = 3.14159265 * pow(h, 4) / 6.0f;
    
    if (0 <= r && r <= h)
    {
        float value = h - r;
        
        //float factor = 315.0 / (64.0 * 3.14159265 * pow(abs(h), 9.0f));
        return value * value / smoothFunctionVolume;
    }
    else
    {
        return 0.0f;
    }
}

float GetParticleInfluenceSlopeSharp(float r, float h)
{
    if (r >= h)
        return 0.0f;
    
    float factor = -6 / (3.14159265 * pow(h, 4));

    float f = (h - r);
    
    float slope = factor * f;

    return slope;
}

float GetParticleInfluenceSharpV2(float r, float h)
{
    h = abs(h);
    
    float smoothFunctionVolume = 3.14159265 * pow(h, 6) / 15.0f;
    
    if (0 <= r && r <= h)
    {
        float value = h - r;
        
        //float factor = 315.0 / (64.0 * 3.14159265 * pow(abs(h), 9.0f));
        return value * value * value * value / smoothFunctionVolume;
    }
    else
    {
        return 0.0f;
    }
}

float GetParticleInfluenceSharpV3(float r, float h)
{
    h = abs(h);
    
    float smoothFunctionVolume = 3.14159265 * pow(h, 7) / 21.0f;
    
    if (0 <= r && r <= h)
    {
        float value = h - r;
        
        //float factor = 315.0 / (64.0 * 3.14159265 * pow(abs(h), 9.0f));
        return value * value * value * value * value / smoothFunctionVolume;
    }
    else
    {
        return 0.0f;
    }
}

float GetParticleInfluenceSlopeSharpV3(float r, float h)
{
    h = abs(h);
    
    if (r >= h)
        return 0.0f;
    
    float factor = -(5 * 21) / (3.14159265 * pow(h, 7));

    float f = (h - r);
    
    float slope = factor * f * f * f * f;

    return slope;
}


//                OPTIMIZATION

// hash a cell coordinate to a hashed value (by multiplying by a large prime number), 
// which will wrap around based on 
static const int2 offsets2D[9] =
{
    int2(-1, 1),
	int2(0, 1),
	int2(1, 1),
	int2(-1, 0),
	int2(0, 0),
	int2(1, 0),
	int2(-1, -1),
	int2(0, -1),
	int2(1, -1),
};


struct Entry
{
    uint particleIndex;
    uint hash;
    uint cellKey;
};

uint HashCell(int cellX, int cellY)
{
    const int PRIME1 = 15823;
    const int PRIME2 = 14999;

    const int PRIME3 = 31;
    
    int positiveX = cellX < 0 ? abs(PRIME3 + cellX) : cellX + PRIME3;
    int positiveY = cellY < 0 ? abs(PRIME3 + cellY) : cellY + PRIME3;
    
    int hash = positiveX * PRIME1 + positiveY * PRIME2;
    //hash = hash & 0x7fffffff; // force non-negative (mask sign bit)

    return (uint) hash;
}

uint KeyFromHash(uint hash, uint tableSize)
{
    return hash % tableSize;
}


int2 PositionToCellCoord(float2 position, float smoothingRadius, float4 bounds) 
{
    float2 offset = float2(bounds.x, bounds.y);
    return (int2) floor((position - offset) / smoothingRadius);
}


float2 PseudoRandomDir(int seed)
{
    float x = sin(seed * 12.9898);
    float y = cos(seed * 78.233);
    float angle = frac(x + y) * 6.2831853; // 2pi

    return float2(cos(angle), sin(angle));
}


