using System;
using System.Threading.Tasks;
using UnityEngine;


public class FluidRenderer2D : ComputeShaderRenderer
{
    // bounds
    public BoxCollider2D boundsCollider;
    public BoxCollider2D spawnCollider;
    public BoxCollider2D otherCollider;

    Bounds bounds;
    Bounds spawnBounds;

    Vector4 boundsVector;

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
    public Color mainParticleColor;
    public Color mediumColor;
    public Color fastishColor;
    public Color fastColor;

    // buffers
    ComputeBuffer particleBuffer;
    ComputeBuffer spatialBuffer;
    ComputeBuffer startIndicesBuffer;


    // kernels
    int colorParticleKernel;
    int moveParticleKernel;
    int computeDensityKernel;
    int externalForceKernel;

    int pressureKernel;
    int viscosityKernel;


    protected override void Awake()
    {
        base.Awake();

        spawnBounds = spawnCollider.bounds;

        // Create particle buffer
        particleBuffer = new ComputeBuffer(particleCount, sizeof(float) * 9);

        spatialBuffer = new ComputeBuffer(particleCount, sizeof(uint) * 3);
        startIndicesBuffer = new ComputeBuffer(particleCount, sizeof(uint));

        particles = new Particle2D[particleCount];
        for (int i = 0; i < particleCount; i++)
        {
            particles[i] = new Particle2D
            {
                position = new Vector2(
                    UnityEngine.Random.Range(spawnBounds.min.x + particleRadius, spawnBounds.max.x - particleRadius),
                    UnityEngine.Random.Range(spawnBounds.min.y + particleRadius, spawnBounds.max.y - particleRadius)
                ),
                velocity = Vector2.zero,
                radius = particleRadius,
                predictedPosition = particles[i].position,
                density = 0.0f,
                nearDensity = 0.0f
            };

            //print(particleData[i].position);
        }
        particleBuffer.SetData(particles);

        colorParticleKernel = computeShader.FindKernel("CSMain");
        moveParticleKernel = computeShader.FindKernel("MoveParticles");
        computeDensityKernel = computeShader.FindKernel("ComputeDensities");
        externalForceKernel = computeShader.FindKernel("ApplyExternalForce");

        pressureKernel = computeShader.FindKernel("ApplyPressure");
        viscosityKernel = computeShader.FindKernel("ApplyViscosity");

        computeShader.SetBuffer(colorParticleKernel, "particles", particleBuffer);
        computeShader.SetBuffer(moveParticleKernel, "particles", particleBuffer);
        computeShader.SetBuffer(computeDensityKernel, "particles", particleBuffer);
        computeShader.SetBuffer(externalForceKernel, "particles", particleBuffer);

        computeShader.SetBuffer(pressureKernel, "particles", particleBuffer);
        computeShader.SetBuffer(viscosityKernel, "particles", particleBuffer);
    }

    protected override void SetShaderParameters()
    {
        base.SetShaderParameters();

        computeShader.SetInt("particleCount", particleCount);
        computeShader.SetVector("screenBounds", new Vector2(Screen.width, Screen.height));

        Vector2 texSize = new Vector2(renderTexture.width, renderTexture.height);
        Vector2 camSize = new Vector2(
            Camera.main.orthographicSize * 2 * Camera.main.aspect,
            Camera.main.orthographicSize * 2
        );
        computeShader.SetVector("TextureSize", texSize);
        computeShader.SetVector("CameraSize", camSize);
        computeShader.SetVector("CameraCenter", Camera.main.transform.position);

        computeShader.SetVector("mainColor", mainParticleColor);
        computeShader.SetVector("fastColor", fastColor);
        computeShader.SetVector("fastishColor", fastishColor);
        computeShader.SetVector("midColor", mediumColor);

    }

    protected override void Update()
    {

    }


    protected void FixedUpdate()
    {
        UpdateSpatialLookup();

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

        bool clicking = Input.GetMouseButton(0);
        bool rightClicking = Input.GetMouseButton(1);

        computeShader.SetFloat("mouseForce", clicking ? mouseForce : -mouseForce);
        computeShader.SetFloat("mouseRadius", mouseRadius);
        computeShader.SetVector("mouseCenter", Camera.main.ScreenToWorldPoint(Input.mousePosition));
        computeShader.SetBool("isClicking", clicking || rightClicking);

        computeShader.SetFloat("deltaTime", Time.fixedDeltaTime);

        bounds = boundsCollider.bounds;

        boundsVector = new Vector4(
            bounds.center.x - bounds.extents.x,
            bounds.center.y - bounds.extents.y,
            bounds.center.x + bounds.extents.x,
            bounds.center.y + bounds.extents.y
        );

        computeShader.SetVector("bounds", boundsVector);


        computeShader.SetVector("otherBoundsCenter", otherCollider.bounds.center);
        computeShader.SetVector("otherBoundsExtents", otherCollider.bounds.extents);

        computeShader.SetFloat("cornerPushback", cornerPushback);

        Render();
        Dispatch();
    }


    Particle2D[] particles;

    Entry[] spatialLookup;

    uint[] startIndices;

    public void UpdateSpatialLookup()
    {
        particles = new Particle2D[particleCount];
        particleBuffer.GetData(particles);

        //print(particleData[0].densityMultiplier);

        spatialLookup = new Entry[particleCount];
        startIndices = new uint[particleCount];

        int num = 0;

        // Create (unordered) spatial lookup
        Parallel.For(0, particleCount, i =>
        {
            (int cellX, int cellY) = PositionToCellCoord(particles[i].position, smoothingRadius);
            uint hash = HashCell(cellX, cellY);
            uint cellKey = KeyFromHash(hash, (uint)particleCount);
            spatialLookup[i] = new Entry((uint)i, hash, cellKey);
            startIndices[i] = int.MaxValue; // Reset start index

            if (particles[i].velocity == Vector2.positiveInfinity || particles[i].density == 0)
            {
                num++;
            }
        });

        //print(num);

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

        //(int, int) leftCell = PositionToCellCoord(new Vector2(-1.1f, 0f), smoothingRadius);
        //(int, int) rightCell = PositionToCellCoord(new Vector2(+1.1f, 0f), smoothingRadius);

        //uint leftHash = HashCell(leftCell.Item1, leftCell.Item2);
        //uint rightHash = HashCell(rightCell.Item1, rightCell.Item2);

        //Debug.Log($"LEFT key = {leftHash}, RIGHT key = {rightHash}");
        //// buffer that shit
        //spatialBuffer = new ComputeBuffer(particleCount, sizeof(int) * 2);
        //startIndicesBuffer = new ComputeBuffer(particleCount, sizeof(int) * 1);

        spatialBuffer.SetData(spatialLookup);
        startIndicesBuffer.SetData(startIndices);

        //int colorParticleKernel = computeShader.FindKernel("CSMain");
        //int moveParticleKernel = computeShader.FindKernel("MoveParticles");
        //int densityKernel = computeShader.FindKernel("ComputeDensities");

        computeShader.SetBuffer(colorParticleKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(moveParticleKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(computeDensityKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(pressureKernel, "spatialLookup", spatialBuffer);
        computeShader.SetBuffer(viscosityKernel, "spatialLookup", spatialBuffer);

        computeShader.SetBuffer(colorParticleKernel, "startIndices", startIndicesBuffer);
        computeShader.SetBuffer(moveParticleKernel, "startIndices", startIndicesBuffer);
        computeShader.SetBuffer(computeDensityKernel, "startIndices", startIndicesBuffer);
        computeShader.SetBuffer(pressureKernel, "startIndices", startIndicesBuffer);
        computeShader.SetBuffer(viscosityKernel, "startIndices", startIndicesBuffer);

        //for (int i = 0; i < spatialLookup.Length; i++)
        //{
        //    Entry entry = spatialLookup[i];
        //    Debug.Log($"Index {i}: CellKey = {entry.cellKey}, ParticleIndex = {entry.particleIndex}");
        //}
    }

    protected override void Dispatch()
    {
        base.Dispatch();

        int numThreads = Mathf.CeilToInt(particleCount / 64.0f);

        computeShader.Dispatch(computeDensityKernel, numThreads, 1, 1);
        computeShader.Dispatch(externalForceKernel, numThreads, 1, 1);

        computeShader.Dispatch(pressureKernel, numThreads, 1, 1);
        computeShader.Dispatch(viscosityKernel, numThreads, 1, 1);

        computeShader.Dispatch(moveParticleKernel, numThreads, 1, 1);

        // update spatial lookup dispatch
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


    uint HashCell(int cellX, int cellY)
    {
        const int PRIME1 = 15823;
        const int PRIME2 = 14999;

        const int PRIME3 = 31;

        int positiveX = cellX < 0 ? Mathf.Abs(PRIME3 + cellX) : cellX + PRIME3;
        int positiveY = cellY < 0 ? Mathf.Abs(PRIME3 + cellY) : cellY + PRIME3;

        int hash = positiveX * PRIME1 + positiveY * PRIME2;
        //hash = hash & 0x7fffffff; // force non-negative (mask sign bit)

        return (uint)hash;
    }

    //(int, int) PositionToCellCoord(Vector2 position, float smoothingRadius)
    //{
    //    const int PRIME3 = 997;

    //    float positiveX = (int) Mathf.Abs(PRIME3 + position.x);
    //    float positiveY = (int) Mathf.Abs(PRIME3 + position.y);

    //    return ((int) Mathf.Floor(positiveX / smoothingRadius), (int) Mathf.Floor(positiveY / smoothingRadius));
    //}

    (int, int) PositionToCellCoord(Vector2 position, float smoothingRadius)
    {

        int x = (int)((position.x - boundsVector.x) / smoothingRadius);
        int y = (int)((position.y - boundsVector.y) / smoothingRadius);

        return (x, y);
    }

    uint KeyFromHash(uint hash, uint tableSize)
    { 
        return hash % tableSize; 
    }

}
