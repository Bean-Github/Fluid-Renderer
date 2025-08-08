using UnityEngine;
using UnityEngine.Experimental.Rendering;
using System.Collections.Generic;
using System;

public class ComputeHelper : MonoBehaviour
{
    public enum DepthMode
    {
        None = 0,
        Depth16 = 16,
        Depth24 = 24
    }
    static readonly uint[] argsBufferArray = new uint[5];

    public static ComputeBuffer CreateArgsBuffer(Mesh mesh, int numInstances)
    {
        const int stride = sizeof(uint);
        const int numArgs = 5;

        const int subMeshIndex = 0;
        uint[] args = new uint[numArgs];
        args[0] = (uint)mesh.GetIndexCount(subMeshIndex);
        args[1] = (uint)numInstances;
        args[2] = (uint)mesh.GetIndexStart(subMeshIndex);
        args[3] = (uint)mesh.GetBaseVertex(subMeshIndex);
        args[4] = 0; // offset

        ComputeBuffer argsBuffer = new ComputeBuffer(numArgs, stride, ComputeBufferType.IndirectArguments);
        argsBuffer.SetData(args);
        return argsBuffer;
    }
    public static void CreateArgsBuffer(ref ComputeBuffer buffer, uint[] args)
    {
        const int stride = sizeof(uint);
        const int numArgs = 5;
        if (buffer == null || buffer.stride != stride || buffer.count != numArgs || !buffer.IsValid())
        {
            buffer = new ComputeBuffer(numArgs, stride, ComputeBufferType.IndirectArguments);
        }

        buffer.SetData(args);
    }
    public static void CreateArgsBuffer(ref ComputeBuffer argsBuffer, Mesh mesh, int numInstances)
    {
        const int stride = sizeof(uint);
        const int numArgs = 5;
        const int subMeshIndex = 0;

        bool createNewBuffer = argsBuffer == null || !argsBuffer.IsValid() || argsBuffer.count != argsBufferArray.Length || argsBuffer.stride != stride;
        if (createNewBuffer)
        {
            Release(argsBuffer);
            argsBuffer = new ComputeBuffer(numArgs, stride, ComputeBufferType.IndirectArguments);
        }

        lock (argsBufferArray)
        {
            argsBufferArray[0] = (uint)mesh.GetIndexCount(subMeshIndex);
            argsBufferArray[1] = (uint)numInstances;
            argsBufferArray[2] = (uint)mesh.GetIndexStart(subMeshIndex);
            argsBufferArray[3] = (uint)mesh.GetBaseVertex(subMeshIndex);
            argsBufferArray[4] = 0; // offset

            argsBuffer.SetData(argsBufferArray);
        }
    }

    public static RenderTexture CreateRenderTexture(int width, int height, FilterMode filterMode, GraphicsFormat format, string name = "Unnamed", DepthMode depthMode = DepthMode.None, bool useMipMaps = false)
    {
        RenderTexture texture = new RenderTexture(width, height, (int)depthMode);
        texture.graphicsFormat = format;
        texture.enableRandomWrite = true;
        texture.autoGenerateMips = false;
        texture.useMipMap = useMipMaps;
        texture.Create();

        texture.name = name;
        texture.wrapMode = TextureWrapMode.Clamp;
        texture.filterMode = filterMode;
        return texture;
    }

    public static bool CreateRenderTexture(ref RenderTexture texture, int width, int height, FilterMode filterMode, GraphicsFormat format, string name = "Unnamed", DepthMode depthMode = DepthMode.None, bool useMipMaps = false)
    {
        if (texture == null || !texture.IsCreated() || texture.width != width || texture.height != height || texture.graphicsFormat != format || texture.depth != (int)depthMode || texture.useMipMap != useMipMaps)
        {
            if (texture != null)
            {
                texture.Release();
            }

            texture = CreateRenderTexture(width, height, filterMode, format, name, depthMode, useMipMaps);
            return true;
        }
        else
        {
            texture.name = name;
            texture.wrapMode = TextureWrapMode.Clamp;
            texture.filterMode = filterMode;
        }

        return false;
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


    /// Releases supplied buffer/s if not null
    public static void Release(params ComputeBuffer[] buffers)
    {
        for (int i = 0; i < buffers.Length; i++)
        {
            if (buffers[i] != null)
            {
                buffers[i].Release();
            }
        }
    }

    /// Releases supplied render textures/s if not null
    public static void Release(params RenderTexture[] textures)
    {
        for (int i = 0; i < textures.Length; i++)
        {
            if (textures[i] != null)
            {
                textures[i].Release();
            }
        }
    }
}
