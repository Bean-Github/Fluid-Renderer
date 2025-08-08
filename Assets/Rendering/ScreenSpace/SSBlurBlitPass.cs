using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UIElements;

internal class SSBlurBlitPass : ScriptableRenderPass
{

    private float m_BlurSize;
    private float m_BlurSmoothness;
    private float m_DepthFactor;
    Matrix4x4 cameraToWorldMatrix => Camera.main.cameraToWorldMatrix;
    Matrix4x4 projectionMatrix => Camera.main.projectionMatrix;
    Matrix4x4 worldToCameraMatrix => Camera.main.worldToCameraMatrix;
    Matrix4x4 projectionInverseMatrix => Camera.main.projectionMatrix.inverse;

    void SetValues()
    {
        var camTex = Shader.PropertyToID("_CameraOpaqueTexture");
        var tex = Shader.GetGlobalTexture(camTex);
        if (tex != null)
        {
            Vector4 texelSize = new Vector4(1f / tex.width, 1f / tex.height, tex.width, tex.height);

            Vector4 texelSizeUpscaled = new Vector4(1f / (tex.width * 2), 1f / (tex.height * 2), tex.width * 2, tex.height * 2);

            Shader.SetGlobalVector("_CameraOpaqueTexture_TexelSize", texelSize);

            Shader.SetGlobalVector("_MainTex_TexelSize", texelSize);

            Shader.SetGlobalVector("_DepthMap_TexelSize", texelSize);

            Shader.SetGlobalVector("_CameraDepthTexture_TexelSize", texelSize);
        }

        m_Material.SetFloat("_BlurSize", m_BlurSize);
        m_Material.SetFloat("_BlurSmoothness", m_BlurSmoothness);
        m_Material.SetFloat("_DepthFactor", m_DepthFactor);
    }

    // gets the values from the renderer feature
    public void SetTarget(RTHandle colorHandle, BlitSettings blitSettings)
    {
        m_CameraColorTarget = colorHandle;

        if (blitSettings == null)
            blitSettings = new ScreenSpaceSettings();

        ScreenSpaceSettings screenSpaceSettings = blitSettings as ScreenSpaceSettings;

        m_BlurSize = screenSpaceSettings.blurSize;
        m_BlurSmoothness = screenSpaceSettings.blurSmoothness;

        m_DepthFactor = screenSpaceSettings.depthFactor;
    }



    // unity stuff

    ProfilingSampler m_ProfilingSampler = new ProfilingSampler("ColorBlit");
    Material m_Material;
    RTHandle m_CameraColorTarget;

    public SSBlurBlitPass(Material material)
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


            cmd.SetGlobalMatrix("_CameraToWorld", cameraToWorldMatrix);
            cmd.SetGlobalMatrix("_CameraInvProjection", projectionInverseMatrix);
            cmd.SetGlobalMatrix("_CameraProjection", projectionMatrix);
            cmd.SetGlobalMatrix("_WorldToCamera", worldToCameraMatrix);

            // TEMP BUFFERS - FULL RTHandle style
            int upscale = 2;

            RTHandle tempRT1 = RTHandles.Alloc(desc.width, desc.height, name: "_TempBlurRT1");
            tempRT1.rt.wrapMode = TextureWrapMode.Clamp;

            RTHandle tempRT2 = RTHandles.Alloc(desc.width, desc.height, name: "_TempBlurRT2");
            tempRT2.rt.wrapMode = TextureWrapMode.Clamp;

            RTHandle tempRT3 = RTHandles.Alloc(desc.width, desc.height, name: "_TempBlurRT3");
            tempRT3.rt.wrapMode = TextureWrapMode.Clamp;

            m_Material.SetTexture("_DepthMap", m_CameraColorTarget);

            // PASS 1 - Horizontal blur
            Blitter.BlitCameraTexture(cmd, m_CameraColorTarget, tempRT1, m_Material, 0);


            // PASS 2 - Vertical blur
            m_Material.SetTexture("_MainTex", tempRT1);

            Blitter.BlitCameraTexture(cmd, tempRT1, tempRT2, m_Material, 1);


            // PASS 3 - Normals
            m_Material.SetTexture("_DepthMap", tempRT2);

            Blitter.BlitCameraTexture(cmd, tempRT2, tempRT3, m_Material, 2);


            // PASS 4 - Color
            m_Material.SetTexture("_ColorTex", tempRT3);

            Blitter.BlitCameraTexture(cmd, tempRT3, m_CameraColorTarget, m_Material, 3);


            // Release temps
            RTHandles.Release(tempRT1);

            RTHandles.Release(tempRT2);

            RTHandles.Release(tempRT3);
        }


        //cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3, 1);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        CommandBufferPool.Release(cmd);
    }



}



