using System;
using System.Threading.Tasks;
using Unity.Mathematics;
using UnityEngine;

public class SpatialHash : MonoBehaviour
{
    float smoothingRadius;
    Bounds bounds;

    public void SetValues(float smoothingRadius, Bounds bounds)
    {
        this.smoothingRadius = smoothingRadius;
        this.bounds = bounds;
    }

    public ComputeShader spatialHashCompute;


    int createSpatialLookupKernel;
    int sortKernel;
    int calculateStartIndicesKernel;

    ComputeBuffer spatialLookupBuffer;
    ComputeBuffer startIndicesBuffer;

    int particleCount;

    public (ComputeBuffer, ComputeBuffer) UpdateSpatialLookup(ComputeBuffer particleBuffer)
    {
        particleCount = particleBuffer.count;

        createSpatialLookupKernel = spatialHashCompute.FindKernel("CreateSpatialLookup");
        sortKernel = spatialHashCompute.FindKernel("SortSpatialLookup");
        calculateStartIndicesKernel = spatialHashCompute.FindKernel("CalculateStartIndices");

        spatialHashCompute.SetBuffer(createSpatialLookupKernel, "particleData", particleBuffer);
        spatialHashCompute.SetBuffer(sortKernel, "particleData", particleBuffer);
        spatialHashCompute.SetBuffer(calculateStartIndicesKernel, "particleData", particleBuffer);

        spatialLookupBuffer = new ComputeBuffer(particleCount, sizeof(uint) * 3);
        startIndicesBuffer = new ComputeBuffer(particleCount, sizeof(uint));

        spatialHashCompute.SetBuffer(createSpatialLookupKernel, "spatialLookup", spatialLookupBuffer);
        spatialHashCompute.SetBuffer(sortKernel, "spatialLookup", spatialLookupBuffer);
        spatialHashCompute.SetBuffer(calculateStartIndicesKernel, "spatialLookup", spatialLookupBuffer);

        spatialHashCompute.SetBuffer(calculateStartIndicesKernel, "startIndices", startIndicesBuffer);
        spatialHashCompute.SetBuffer(sortKernel, "startIndices", startIndicesBuffer);
        spatialHashCompute.SetBuffer(createSpatialLookupKernel, "startIndices", startIndicesBuffer);


        // Set other parameters
        spatialHashCompute.SetInt("particleCount", particleCount);
        spatialHashCompute.SetFloat("smoothingRadius", smoothingRadius);
        spatialHashCompute.SetVector("boundsCenter", bounds.center);
        spatialHashCompute.SetVector("boundsExtents", bounds.extents);

        // then dispatch stuff
        return Dispatch();
    }


    // do all this within compute shader
    // Based on positions, decide which particles are in which spatial cells.
    private (ComputeBuffer, ComputeBuffer) Dispatch()
    {
        spatialHashCompute.Dispatch(createSpatialLookupKernel, Mathf.CeilToInt(particleCount / 64f), 1, 1); // 64 threads per group?

        // Sort by cell key!!
        DispatchSort();

        // Calculate start indices of each unique cell key in the spatial lookup
        spatialHashCompute.Dispatch(calculateStartIndicesKernel, Mathf.CeilToInt(particleCount / 64f), 1, 1); // 64 threads per group

        return (
            spatialLookupBuffer,
            startIndicesBuffer
        );
    }

    void DispatchSort()
    {
        int numPairs = Mathf.CeilToInt(BitonicSort.NextPowerOfTwo(particleCount) / 2);

        int numStages = (int)Mathf.Log(numPairs * 2, 2);

        for (int stageIndex = 0; stageIndex < numStages; stageIndex++)
        {
            int height = 1 << (stageIndex + 1);  // for determining accending or descending order, 2 4 8 16 32

            for (int stepIndex = 0; stepIndex < stageIndex + 1; stepIndex++)
            {
                int width = 1 << (stageIndex - stepIndex);  // 2 ^ (stageIndex - stepIndex)

                spatialHashCompute.SetInt("width", width);
                spatialHashCompute.SetInt("height", height);

                spatialHashCompute.Dispatch(sortKernel, numPairs, 1, 1); // one thread per pair
            }
        }
    }

    private void OnDestroy()
    {
        spatialLookupBuffer?.Release();
        startIndicesBuffer?.Release();
    }

    private void OnDisable()
    {
        spatialLookupBuffer?.Release();
        startIndicesBuffer?.Release();
    }
}