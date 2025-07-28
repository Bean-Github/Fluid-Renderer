using System;
using System.Threading.Tasks;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.UIElements;
using static UnityEngine.EventSystems.EventTrigger;

public class FluidRenderer3DCombined : ComputeShaderRenderer
{
    // bounds
    public BoxCollider boundsCollider;
    public BoxCollider spawnCollider;
    //public BoxCollider otherCollider;

    //public Transform particlesParent;

    public SpatialHash spatialHash;

    Bounds bounds;
    Bounds spawnBounds;

    // basics
    public int particleCount = 1;
    public float gravity = 1.0f;

    public float mass = 1.0f;

    // pressure
    [Range(0.0f, 1.0f)]
    public float boundsDamping = 0.5f;

    public float smoothingRadius;

    public float targetDensity;
    public float pressureMultiplier;
    public float nearPressureMultiplier;

    public float cornerPushback;

    // friction
    public float maxVelocity = 10.0f;
    public float viscosity;
    public float slowdownAmount;

    // external fun
    public float mouseForce;
    public float mouseRadius;

    // buffers
    ComputeBuffer particleBuffer;
    ComputeBuffer spatialBuffer;
    ComputeBuffer startIndicesBuffer;

    // densityMultiplier map
    [Header("Density Map Settings")]
    public bool useDensityMap = false;
    public RenderTexture densityMap;
    public int densityTextureRes;

    [Header("Particle Render Settings")]
    public bool renderParticles = true;
    public float particleRadius = 0.1f;
    public ParticleManager particleManager;

    // kernels
    int moveParticleKernel;
    int densityMapKernel;

    protected override void Awake()
    {
        base.Awake();

        // initialize particles for rendering
        //particleManager?.Initialize(particleCount, maxVelocity);
    }

    protected override void CreateBuffers()
    {
        base.CreateBuffers();

        // Create particle buffer
        particleBuffer = new ComputeBuffer(particleCount, sizeof(float) * 12);

        particleData = new Particle3D[particleCount];

        spawnBounds = spawnCollider.bounds;

        for (int i = 0; i < particleCount; i++)
        {
            particleData[i] = new Particle3D
            {
                position = new Vector3(
                    UnityEngine.Random.Range(spawnBounds.min.x + particleRadius, spawnBounds.max.x - particleRadius),
                    UnityEngine.Random.Range(spawnBounds.min.y + particleRadius, spawnBounds.max.y - particleRadius),
                    UnityEngine.Random.Range(spawnBounds.min.z + particleRadius, spawnBounds.max.z - particleRadius)
                ),
                velocity = Vector3.zero,
                radius = particleRadius,
                predictedPosition = particleData[i].position,
                density = 0.0f,
                nearDensity = 0.0f
            };
        }

        particleBuffer.SetData(particleData);


        spatialBuffer = new ComputeBuffer(particleCount, sizeof(uint) * 3);
        startIndicesBuffer = new ComputeBuffer(particleCount, sizeof(uint));
    }

    protected override void SetKernelsAndBuffers()
    {
        base.SetKernelsAndBuffers();

        //colorParticleKernel = computeShader.FindKernel("CSMain");
        moveParticleKernel = computeShader.FindKernel("MoveParticles");
        densityMapKernel = computeShader.FindKernel("RenderDensityMap");

        // set buffers
        computeShader.SetBuffer(moveParticleKernel, "particles", particleBuffer);
        computeShader.SetBuffer(densityMapKernel, "particles", particleBuffer);
    }

    protected override void SetShaderParameters()
    {
        base.SetShaderParameters();

        computeShader.SetInt("particleCount", particleCount);
        //computeShader.SetVector("screenBounds", new Vector2(Screen.width, Screen.height));

        Vector2 texSize = new Vector2(renderTexture.width, renderTexture.height);
        Vector2 camSize = new Vector2(
            Camera.main.orthographicSize * 2 * Camera.main.aspect,
            Camera.main.orthographicSize * 2
        );

    }

    protected override void SetRealtimeShaderParameters()
    {
        base.SetRealtimeShaderParameters();

        bounds = boundsCollider.bounds;

        computeShader.SetVector("boundsCenter", bounds.center);
        computeShader.SetVector("boundsExtents", bounds.extents);

        computeShader.SetFloat("deltaTime", Time.deltaTime);

        computeShader.SetMatrix("localToWorld", boundsCollider.transform.localToWorldMatrix);
        computeShader.SetMatrix("worldToLocal", boundsCollider.transform.worldToLocalMatrix);

        bool clicking = Input.GetMouseButton(0);
        bool rightClicking = Input.GetMouseButton(1);

        computeShader.SetFloat("mouseForce", clicking ? mouseForce : -mouseForce);
        computeShader.SetFloat("mouseRadius", mouseRadius);


        computeShader.SetBool("isClicking", clicking || rightClicking);

        spatialHash?.SetValues(smoothingRadius, boundsCollider.bounds);


        // set values for compute shader
        computeShader.SetFloat("gravity", gravity);

        computeShader.SetFloat("smoothingRadius", smoothingRadius);
        computeShader.SetFloat("sqrSmoothingRadius", smoothingRadius * smoothingRadius);
        computeShader.SetFloat("boundsDamping", boundsDamping);

        computeShader.SetFloat("targetDensity", targetDensity);
        computeShader.SetFloat("pressureMultiplier", pressureMultiplier);

        computeShader.SetFloat("nearPressureMultiplier", nearPressureMultiplier);

        computeShader.SetFloat("mass", mass);
        computeShader.SetFloat("slowdown", slowdownAmount);

        computeShader.SetFloat("viscosity", viscosity);

        computeShader.SetFloat("maxVelocity", maxVelocity);


        computeShader.SetFloat("cornerPushback", cornerPushback);
    }


    protected override void Update()
    {
        if (renderParticles) particleManager?.RenderParticles(particleBuffer, particleCount, bounds);
    }


    protected void FixedUpdate()
    {
        UpdateSpatialLookup();

        Dispatch();
        Render(); // obsolete, but kept for compatibility

        // update densityMultiplier map

        if (useDensityMap)
        {
            UpdateDensityMap();
        }
    }

    protected override void Dispatch()
    {
        base.Dispatch();

        int numThreads = Mathf.CeilToInt(particleCount / 64.0f);

        computeShader.Dispatch(moveParticleKernel, numThreads, 1, 1);

    }


    void OnDestroy()
    {
        if (particleBuffer != null)
        {
            particleBuffer.Dispose();
            particleBuffer = null;
        }

        if (spatialBuffer != null)
        {
            spatialBuffer.Dispose();
            spatialBuffer = null;
        }

        if (startIndicesBuffer != null)
        {
            startIndicesBuffer.Dispose();
            startIndicesBuffer = null;
        }
    }


    Particle3D[] particleData;

    // Based on positions, decide which particles are in which spatial cells.
    public void UpdateSpatialLookup()
    {
        (ComputeBuffer a, ComputeBuffer b) = spatialHash.UpdateSpatialLookup(particleBuffer);

        spatialBuffer = a;
        startIndicesBuffer = b;

        SetSpatialBuffers();
    }

    void SetSpatialBuffers()
    {
        computeShader.SetBuffer(moveParticleKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(moveParticleKernel, "startIndices", startIndicesBuffer);

        computeShader.SetBuffer(densityMapKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(densityMapKernel, "startIndices", startIndicesBuffer);
    }

    void UpdateDensityMap()
    {
        // convert bounds to unit and then scale by densityTextureRes
        float maxAxis = Mathf.Max(bounds.size.x, bounds.size.y, bounds.size.z);
        int w = Mathf.RoundToInt(bounds.size.x / maxAxis * densityTextureRes);
        int h = Mathf.RoundToInt(bounds.size.y / maxAxis * densityTextureRes);
        int d = Mathf.RoundToInt(bounds.size.z / maxAxis * densityTextureRes);

        ComputeHelper.CreateRenderTexture3D(ref densityMap, w, h, d, GraphicsFormat.R16_SFloat, TextureWrapMode.Clamp);

        //Debug.Log(w + " " + h + "  " + d);
        computeShader.SetTexture(densityMapKernel, "DensityMap", densityMap);
        computeShader.SetInts("densityMapSize", densityMap.width, densityMap.height, densityMap.volumeDepth);

        // set buffers

        int wi = Mathf.CeilToInt(densityMap.width / 8.0f);
        int hi = Mathf.CeilToInt(densityMap.height / 8.0f);
        int di = Mathf.CeilToInt(densityMap.volumeDepth / 8.0f);

        computeShader.Dispatch(densityMapKernel, wi, hi, di);

    }

}



