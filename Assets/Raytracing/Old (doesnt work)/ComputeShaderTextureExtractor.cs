using UnityEngine;

public class ComputeShaderTextureExtractor : MonoBehaviour
{
    public ComputeShader computeShader;
    public RenderTexture renderTexture;
    public Texture2D outputTexture;

    void Start()
    {
        int width = 256, height = 256;

        // Create a RenderTexture for the compute shader to write to
        renderTexture = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        renderTexture.enableRandomWrite = true; // Needed for RWTexture2D
        renderTexture.Create();

        // Create a Texture2D to store read-back data
        outputTexture = new Texture2D(width, height, TextureFormat.RGBAFloat, false);

        int kernelHandle = computeShader.FindKernel("CSMain");

        // Set the RWTexture2D in the compute shader
        computeShader.SetTexture(0, "Result", renderTexture);

        // Dispatch the compute shader (256x256 threads with 8x8 groups)
        computeShader.Dispatch(kernelHandle, width / 8, height / 8, 1);

        // Read pixels back from GPU to CPU
        RenderTexture.active = renderTexture;
        outputTexture.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        outputTexture.Apply();
        RenderTexture.active = null;

        // Extract pixel data
        Color pixelColor = outputTexture.GetPixel(128, 128); // Read a pixel from the center
        Debug.Log($"Pixel Color at (128,128): {pixelColor}");

        

        //// Save texture as PNG (optional)
        byte[] bytes = outputTexture.EncodeToPNG();
        System.IO.File.WriteAllBytes(Application.dataPath + "/Output.png", bytes);
        Debug.Log("Texture saved to Output.png");
    }
}

