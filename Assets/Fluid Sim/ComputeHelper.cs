using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class ComputeHelper : MonoBehaviour
{
    public enum DepthMode
    {
        None = 0,
        Depth16 = 16,
        Depth24 = 24
    }

    public static void CreateRenderTexture3D(ref RenderTexture texture, int width, int height, int depth, GraphicsFormat format, TextureWrapMode wrapMode = TextureWrapMode.Repeat, string name = "Untitled", bool mipmaps = false)
    {
        if (texture == null || !texture.IsCreated() || texture.width != width || texture.height != height || texture.volumeDepth != depth || texture.graphicsFormat != format)
        {
            //Debug.Log ("Create tex: update noise: " + updateNoise);
            if (texture != null)
            {
                texture.Release();
            }

            const int numBitsInDepthBuffer = 0;
            texture = new RenderTexture(width, height, numBitsInDepthBuffer);
            texture.graphicsFormat = format;
            texture.volumeDepth = depth;
            texture.enableRandomWrite = true;
            texture.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            texture.useMipMap = mipmaps;
            texture.autoGenerateMips = false;
            texture.Create();
        }

        texture.wrapMode = wrapMode;
        texture.filterMode = FilterMode.Bilinear;
        texture.name = name;
    }

}
