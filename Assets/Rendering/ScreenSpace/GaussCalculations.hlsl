/// VALUES ///

float _BlurSize;

float _BlurSmoothness;

float _DepthFactor;

/// - /// - ///


float4x4 _CameraToWorld;
float4x4 _CameraInvProjection;
float4x4 _CameraProjection;
float4x4 _WorldToCamera;    

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

// Calculate the number of pixels covered by a world-space radius at given dst from camera
float CalculateScreenSpaceRadius(float worldRadius, float depth, int imageWidth)
{
    // Thanks to x.com/FreyaHolmer/status/1820157167682388210
    float widthScale = _CameraProjection._m00; // smaller values correspond to higher fov (objects appear smaller)
    float pxPerMeter = (imageWidth * widthScale) / (2 * depth);
    return abs(pxPerMeter) * worldRadius;
}


Varyings vert(uint vertexID : SV_VertexID)
{
    Varyings o;

                // Fullscreen triangle (no mesh needed)
    float2 positions[3] =
    {
        float2(-1, -1),
        float2(3, -1),
        float2(-1, 3)
    };

    float2 uvs[3] =
    {
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

float GaussianBlurWeight(int x, int y, float sigma)
{
    int sqrDst = x * x + y * y;
    float c = 2 * sigma * sigma;
    return exp(-sqrDst / c);
}
