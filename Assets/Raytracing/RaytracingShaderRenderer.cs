using System.Collections.Generic;
using System.Linq;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Experimental.GlobalIllumination;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RaytracingShaderRenderer : ComputeShaderRenderer
{
    public Texture skyboxTexture;

    public int numReflections;

    public List<Sphere> spheres;

    private ComputeBuffer _sphereBuffer;

    public Light directionalLight;

    protected override void Render()
    {
        base.Render();
        computeShader.SetTexture(kernelHandle, "_SkyboxTexture", skyboxTexture);
    }

    protected override void SetShaderParameters()
    {
        base.SetShaderParameters();

        computeShader.SetInt("_NumReflections", numReflections);

        Vector3 l = directionalLight.transform.forward;

        computeShader.SetVector("_DirectionalLight", new Vector4(l.x, l.y, l.z, directionalLight.intensity));

        _sphereBuffer = new ComputeBuffer(spheres.Count, 40);
        _sphereBuffer.SetData(spheres);

        computeShader.SetBuffer(0, "_Spheres", _sphereBuffer);
    }


}

