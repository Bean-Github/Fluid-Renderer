using UnityEngine;

public class BitonicSort : MonoBehaviour
{
    public int[] originalArray;

    public ComputeShader bitonicSortCompute;

    private ComputeBuffer valuesBuffer;


    [ContextMenu("Sort")]
    void Sort()
    {
        Setup();

        Dispatch();

        ReceiveValues();
    }

    int paddedLength;

    void Setup()
    {
        paddedLength = NextPowerOfTwo(originalArray.Length);

        valuesBuffer = new ComputeBuffer(paddedLength, sizeof(int));

        int[] paddedArray = new int[paddedLength];

        for (int i = 0; i < originalArray.Length; i++)
            paddedArray[i] = originalArray[i];

        // Pad the rest with MAX_INT (or whatever keeps sort order clean)
        for (int i = originalArray.Length; i < paddedLength; i++)
            paddedArray[i] = int.MaxValue;


        valuesBuffer.SetData(paddedArray);

        bitonicSortCompute.SetBuffer(0, "Values", valuesBuffer);

        bitonicSortCompute.SetInt("numValues", paddedLength);
    }

    void Dispatch()
    {
        int kernelHandle = bitonicSortCompute.FindKernel("CSMain");

        int numPairs = Mathf.CeilToInt(paddedLength / 2);

        int numStages = (int)Mathf.Log(numPairs * 2, 2);

        for (int stageIndex = 0; stageIndex < numStages; stageIndex++)
        {
            int height = 1 << (stageIndex + 1);  // for determining accending or descending order, 2 4 8 16 32

            for (int stepIndex = 0; stepIndex < stageIndex + 1; stepIndex++)
            {
                int width = 1 << (stageIndex - stepIndex);  // 2 ^ (stageIndex - stepIndex)

                bitonicSortCompute.SetInt("width", width);
                bitonicSortCompute.SetInt("height", height);

                bitonicSortCompute.Dispatch(kernelHandle, numPairs, 1, 1); // one thread per pair

            }
        }
    }

    void ReceiveValues()
    {
        int[] ints = new int[originalArray.Length];

        valuesBuffer.GetData(ints);

        string result = string.Join(", ", ints);

        print(result);
    }

    public static int NextPowerOfTwo(int value)
    {
        if (value < 1) return 1;

        value--;
        value |= value >> 1;
        value |= value >> 2;
        value |= value >> 4;
        value |= value >> 8;
        value |= value >> 16;
        return value + 1;
    }


    private void OnDestroy()
    {
        valuesBuffer?.Release();
    }

    private void OnDisable()
    {
        valuesBuffer?.Release();
    }
}
