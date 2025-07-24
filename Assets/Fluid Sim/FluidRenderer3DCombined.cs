using System;
using System.Threading.Tasks;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.UIElements;
using static UnityEngine.EventSystems.EventTrigger;

public class FluidRenderer3DCombined : ComputeShaderRenderer
{
    public GameObject particlePrefab;

    // bounds
    public BoxCollider boundsCollider;
    public BoxCollider spawnCollider;
    //public BoxCollider otherCollider;

    //public Transform particlesParent;

    public ParticleManager particleManager;

    Bounds bounds;
    Bounds spawnBounds;

    // basics
    public int particleCount = 1;
    public float gravity = 1.0f;

    public float mass = 1.0f;

    public float particleRadius = 0.1f;

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

    // colors
    //public Color mainParticleColor;
    //public Color mediumColor;
    //public Color fastishColor;
    //public Color fastColor;

    // buffers
    ComputeBuffer particleBuffer;
    ComputeBuffer spatialBuffer;
    ComputeBuffer startIndicesBuffer;


    // kernels
    int colorParticleKernel;  // obsolete
    int moveParticleKernel;
    int computeDensityKernel;
    int externalForceKernel;

    int pressureKernel;
    int viscosityKernel;


    protected override void Awake()
    {
        base.Awake();

        // initialize particles for rendering
        particleManager?.Initialize(particleCount, maxVelocity);
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
        computeDensityKernel = computeShader.FindKernel("ComputeDensities");
        externalForceKernel = computeShader.FindKernel("ApplyExternalForce");

        pressureKernel = computeShader.FindKernel("ApplyPressure");
        viscosityKernel = computeShader.FindKernel("ApplyViscosity");

        // set buffers
        //computeShader.SetBuffer(colorParticleKernel, "particles", particleBuffer);
        computeShader.SetBuffer(moveParticleKernel, "particles", particleBuffer);
        //computeShader.SetBuffer(computeDensityKernel, "particles", particleBuffer);
        //computeShader.SetBuffer(externalForceKernel, "particles", particleBuffer);
        //computeShader.SetBuffer(pressureKernel, "particles", particleBuffer);
        //computeShader.SetBuffer(viscosityKernel, "particles", particleBuffer);
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

        computeShader.SetFloat("deltaTime", Time.fixedDeltaTime);


        computeShader.SetFloat("cornerPushback", cornerPushback);
    }

    protected override void SetRealtimeShaderParameters()
    {
        base.SetRealtimeShaderParameters();

        bounds = boundsCollider.bounds;

        computeShader.SetVector("boundsCenter", bounds.center);
        computeShader.SetVector("boundsExtents", bounds.extents);

        computeShader.SetMatrix("localToWorld", boundsCollider.transform.localToWorldMatrix);
        computeShader.SetMatrix("worldToLocal", boundsCollider.transform.worldToLocalMatrix);

        bool clicking = Input.GetMouseButton(0);
        bool rightClicking = Input.GetMouseButton(1);

        computeShader.SetFloat("mouseForce", clicking ? mouseForce : -mouseForce);
        computeShader.SetFloat("mouseRadius", mouseRadius);
        

        computeShader.SetBool("isClicking", clicking || rightClicking);
    }


    protected override void Update()
    {
        particleManager?.RenderParticles(particleData);
    }


    protected void FixedUpdate()
    {
        UpdateSpatialLookup();

        Dispatch();
        Render();
    }

    protected override void Dispatch()
    {
        base.Dispatch();

        int numThreads = Mathf.CeilToInt(particleCount / 64.0f);

        //computeShader.Dispatch(computeDensityKernel, numThreads, 1, 1);
        //computeShader.Dispatch(externalForceKernel, numThreads, 1, 1);

        //computeShader.Dispatch(pressureKernel, numThreads, 1, 1);
        //computeShader.Dispatch(viscosityKernel, numThreads, 1, 1);

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


    #region SpatialLookup

    Particle3D[] particleData;

    Entry[] spatialLookup;

    uint[] startIndices;




    // Based on positions, decide which particles are in which spatial cells.
    public void UpdateSpatialLookup()
    {
        particleBuffer.GetData(particleData);

        spatialLookup = new Entry[particleCount];
        startIndices = new uint[particleCount];

        int num = 0;

        // Create (unordered) spatial lookup
        Parallel.For(0, particleCount, i =>
        {
            (int cellX, int cellY, int cellZ) = PositionToCellCoord(particleData[i].position, smoothingRadius, bounds.center, bounds.extents);
            uint hash = HashCell(cellX, cellY, cellZ);
            uint cellKey = KeyFromHash(hash, (uint)(particleCount));
            spatialLookup[i] = new Entry((uint)i, hash, cellKey);
            startIndices[i] = int.MaxValue; // Reset start index

            if (particleData[i].velocity == Vector3.positiveInfinity || particleData[i].density == 0)
            {
                num++;
            }
        });

        // Sort by cell key
        Array.Sort(spatialLookup);

        // Calculate start indices of each unique cell key in the spatial lookup
        Parallel.For(0, particleCount, i =>
        {
            uint key = spatialLookup[i].cellKey;
            uint keyPrev = i == 0 ? int.MaxValue : spatialLookup[i - 1].cellKey;

            if (key != keyPrev)
            {
                startIndices[key] = (uint) i;
            }
        });

        spatialBuffer.SetData(spatialLookup);
        startIndicesBuffer.SetData(startIndices);

        SetSpatialBuffers();
    }

    void SetSpatialBuffers()
    {
        computeShader.SetBuffer(moveParticleKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(moveParticleKernel, "startIndices", startIndicesBuffer);
    }


    uint HashCell(int cellX, int cellY, int cellZ)
    {
        const int PRIME1 = 15823;
        const int PRIME2 = 14999;
        const int PRIME3 = 9737333;


        const int PRIME4 = 31;

        uint positiveX = (uint)(cellX + PRIME4);
        uint positiveY = (uint)(cellY + PRIME4);
        uint positiveZ = (uint)(cellZ + PRIME4);

        uint hash = positiveX * PRIME1 + positiveY * PRIME2 + positiveZ * PRIME3;
        //hash = hash & 0x7fffffff; // force non-negative (mask sign bit)

        return (uint)hash;
    }

    (int, int, int) PositionToCellCoord(Vector3 position, float smoothingRadius, float3 boundsCenter, float3 boundsExtents)
    {
        // roots position based on the bounds center and extents
        Vector3 offset = new Vector3(boundsCenter.x - boundsExtents.x, boundsCenter.y - boundsExtents.y, boundsCenter.z - boundsExtents.z);

        int x = (int) ((position.x - offset.x) / smoothingRadius);
        int y = (int) ((position.y - offset.y) / smoothingRadius);
        int z = (int) ((position.z - offset.z) / smoothingRadius);

        return (x, y, z);
    }

    uint KeyFromHash(uint hash, uint tableSize)
    { 
        return hash % tableSize; 
    }
    
    #endregion
}



