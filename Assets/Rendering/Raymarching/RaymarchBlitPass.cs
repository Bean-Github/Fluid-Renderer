using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

internal class ColorBlitPass : ScriptableRenderPass
{
    // Key
    float m_DensityMultiplier = 1.0f; // multiplier for the density map
    float m_StepSize; // default step size, can be adjusted

    // Lighting
    float m_LightStepSize = 0.1f; // step size for light refractions
    int m_NumRefractions = 2;

    Vector3 m_ScatteringCoefficients = Vector3.one;

    // Misc
    float m_VolumeValueOffset = 150;

    float m_IndexOfRefraction;

    Vector3 m_BoxBoundsMin;
    Vector3 m_BoxBoundsMax;

    Matrix4x4 cameraToWorldMatrix => Camera.main.cameraToWorldMatrix;
    Matrix4x4 projectionMatrix => Camera.main.projectionMatrix;

    FluidRenderer3DCombined m_FluidRenderer;

    void SetValues()
    {
        m_Material.SetVector("_BoxBoundsMin", m_BoxBoundsMin);
        m_Material.SetVector("_BoxBoundsMax", m_BoxBoundsMax);

        m_Material.SetFloat("_IndexOfRefraction", m_IndexOfRefraction);

        m_Material.SetFloat("_StepSize", m_StepSize);
        m_Material.SetFloat("_DensityMultiplier", m_DensityMultiplier);

        m_Material.SetFloat("_LightStepSize", m_LightStepSize);
        m_Material.SetInt("_NumRefractions", m_NumRefractions);

        m_Material.SetFloat("volumeValueOffset", m_VolumeValueOffset);

        m_Material.SetVector("_ScatteringCoefficients", m_ScatteringCoefficients);


        if (m_FluidRenderer?.densityMap != null)
        {
            m_Material.SetTexture("_DensityMap", m_FluidRenderer.densityMap);
            return;
        }
    }

    // gets the values from the renderer feature
    public void SetTarget(RTHandle colorHandle, BlitSettings blitSettings)
    {
        if (blitSettings == null)
            blitSettings = new RaymarchSettings();

        RaymarchSettings raymarchSettings = blitSettings as RaymarchSettings;

        m_CameraColorTarget = colorHandle;

        // raymarch settings
        m_StepSize = raymarchSettings.stepSize;

        m_DensityMultiplier = raymarchSettings.densityMultiplier;

        // lighting
        m_NumRefractions = raymarchSettings.numRefractions;
        m_LightStepSize = raymarchSettings.lightStepSize;

        // misc
        m_VolumeValueOffset = raymarchSettings.volumeValueOffset;

        if (raymarchSettings.fluidRenderer != null)
        {
            m_FluidRenderer = raymarchSettings.fluidRenderer;
            m_BoxBoundsMin = raymarchSettings.fluidRenderer.boundsCollider.bounds.min;
            m_BoxBoundsMax = raymarchSettings.fluidRenderer.boundsCollider.bounds.max;
        }

        m_IndexOfRefraction = raymarchSettings.indexOfRefraction;

        m_ScatteringCoefficients = raymarchSettings.scatteringCoefficients;
    }



    // unity stuff

    ProfilingSampler m_ProfilingSampler = new ProfilingSampler("ColorBlit");
    Material m_Material;
    RTHandle m_CameraColorTarget;

    public ColorBlitPass(Material material)
    {
        m_Material = material;
        renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        ConfigureTarget(m_CameraColorTarget);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cameraData = renderingData.cameraData;
        if (cameraData.camera.cameraType != CameraType.Game)
            return;

        if (m_Material == null)
            return;

        CommandBuffer cmd = CommandBufferPool.Get();
        using (new ProfilingScope(cmd, m_ProfilingSampler))
        {
            SetValues();
            Blitter.BlitCameraTexture(cmd, m_CameraColorTarget, m_CameraColorTarget, m_Material, 0);
        }

        //cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3, 1);

        cmd.SetGlobalMatrix("_CameraToWorld", cameraToWorldMatrix);
        cmd.SetGlobalMatrix("_CameraInvProjection", projectionMatrix.inverse);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        CommandBufferPool.Release(cmd);
    }

}
