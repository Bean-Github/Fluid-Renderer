using System.Collections.Generic;
using System.Linq;
using Unity.Mathematics;
using UnityEngine;

public class ComputeShaderRenderer : MonoBehaviour
{
    public ComputeShader computeShader;
    public Material blitMaterial;

    public RenderTexture renderTexture;
    protected Camera mainCamera;
    protected int kernelHandle;

    protected int width;
    protected int height;

    protected virtual void Awake()
    {
        mainCamera = Camera.main;

        width = Screen.width;
        height = Screen.height;

        CreateBuffers();

        SetKernelsAndBuffers();

        SetShaderParameters();
    }

    protected virtual void CreateBuffers()
    {

    }

    protected virtual void SetKernelsAndBuffers()
    {
        kernelHandle = computeShader.FindKernel("CSMain");
    }

    protected virtual void SetShaderParameters()
    {
        // Get Camera Matrices
        Matrix4x4 cameraToWorld = mainCamera.cameraToWorldMatrix;
        Matrix4x4 projection = mainCamera.projectionMatrix;
        Matrix4x4 worldToCamera = mainCamera.worldToCameraMatrix;

        computeShader.SetMatrix("_CameraToWorld", cameraToWorld);
        computeShader.SetMatrix("_CameraInverseProjection", projection.inverse);
        computeShader.SetMatrix("_WorldToCamera", worldToCamera);
        computeShader.SetMatrix("_CameraProjection", projection);

        // Set RenderTexture as compute shader output
        computeShader.SetTexture(kernelHandle, "Result", renderTexture);

        InitRenderTexture();
    }

    protected virtual void SetRealtimeShaderParameters()
    {
        
    }

    protected virtual void Update()
    {
        Dispatch();
        Render();
    }

    protected virtual void Render()
    {
        if (mainCamera == null) return;

        SetRealtimeShaderParameters();

        // Blit the compute shader output to the screen
        blitMaterial.SetTexture("_Texture2D", renderTexture);
    }

    protected virtual void Dispatch()
    {
        int threadGroupsX = Mathf.CeilToInt(renderTexture.width / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(renderTexture.height / 8.0f);

        // Dispatch the Compute Shader
        computeShader.Dispatch(kernelHandle, threadGroupsX, threadGroupsY, 1);
    }

    protected void InitRenderTexture()
    {
        if (renderTexture == null || renderTexture.width != width || renderTexture.height != height)
        {
            // Release render texture if we already have one
            if (renderTexture != null)
                renderTexture.Release();

            // Get a render target for Ray Tracing
            renderTexture = new RenderTexture(width, height, 0,
                RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
            renderTexture.enableRandomWrite = true;
            renderTexture.Create();
        }
    }

}







