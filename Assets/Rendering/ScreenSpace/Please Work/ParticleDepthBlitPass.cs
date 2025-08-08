using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

internal class ParticleDepthBlitPass : ScriptableRenderPass
{


    void SetValues()
    {
        //var camTex = Shader.PropertyToID("_CameraOpaqueTexture");
        //var tex = Shader.GetGlobalTexture(camTex);
        //if (tex != null)
        //{
        //    Vector4 texelSize = new Vector4(1f / tex.width, 1f / tex.height, tex.width, tex.height);
        //    Shader.SetGlobalVector("_CameraOpaqueTexture_TexelSize", texelSize);
        //}

        //m_Material.SetFloat("_BlurSize", m_BlurSize);
        //m_Material.SetFloat("_BlurSmoothness", m_BlurSmoothness);

        m_Material.SetFloat("_Scale", radius);
    }

    // gets the values from the renderer feature
    public void SetTarget(RTHandle colorHandle, BlitSettings blitSettings)
    {
        m_CameraColorTarget = colorHandle;

        if (blitSettings == null)
            blitSettings = new ParticleDepthSettings();

        ParticleDepthSettings screenSpaceSettings = blitSettings as ParticleDepthSettings;

        instanceCount = screenSpaceSettings.fluidRenderer.particleCount;
        maxVelocity = screenSpaceSettings.fluidRenderer.maxVelocity;

        radius = screenSpaceSettings.fluidRenderer.particleRadius;

    }

    // unity stuff

    ProfilingSampler m_ProfilingSampler = new ProfilingSampler("ColorBlit");
    Material m_Material;
    RTHandle m_CameraColorTarget;

    Mesh particleMesh;
    ComputeBuffer particleBuffer;
    int instanceCount;
    float maxVelocity;
    float radius;


    public ParticleDepthBlitPass(Material material)
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

            var desc = renderingData.cameraData.cameraTargetDescriptor;

            MaterialPropertyBlock props = new MaterialPropertyBlock();

            props.SetBuffer("particles", particleBuffer);
            props.SetFloat("maxVelocity", maxVelocity);
            props.SetFloat("_NumInstances", instanceCount);

            //cmd.SetRenderTarget(depthRT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
            //cmd.ClearRenderTarget(true, true, Color.clear);

            cmd.DrawMeshInstancedProcedural(particleMesh, 0, m_Material, 0, instanceCount, props);


            Blitter.BlitCameraTexture(cmd, m_CameraColorTarget, m_CameraColorTarget, m_Material, 0);

        }


        //cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3, 1);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        CommandBufferPool.Release(cmd);
    }



}



