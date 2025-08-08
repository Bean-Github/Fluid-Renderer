using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ParticleDepthFeature : ScriptableRendererFeature
{
    class CustomDepthPass : ScriptableRenderPass
    {
        Material depthMat;
        Mesh particleMesh;
        ComputeBuffer particleBuffer;
        int instanceCount;
        float maxVelocity;
        float radius;

        RTHandle depthRT;

        public CustomDepthPass(Material mat, Mesh mesh)
        {
            this.depthMat = mat;
            this.particleMesh = mesh;
            renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
        }

        public void Setup(ComputeBuffer buffer, int count, float maxVel, float rad, RTHandle targetRT)
        {
            particleBuffer = buffer;
            instanceCount = count;
            maxVelocity = maxVel;
            radius = rad;
            depthRT = targetRT;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (depthMat == null || particleMesh == null || particleBuffer == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("Render Particle Depth");

            MaterialPropertyBlock props = new MaterialPropertyBlock();

            props.SetBuffer("particles", particleBuffer);
            props.SetFloat("maxVelocity", maxVelocity);
            props.SetFloat("_NumInstances", instanceCount);

            cmd.SetRenderTarget(depthRT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
            cmd.ClearRenderTarget(true, true, Color.clear);

            cmd.DrawMeshInstancedProcedural(particleMesh, 0, depthMat, 0, instanceCount, props);

            context.ExecuteCommandBuffer(cmd);

            

            cmd.Blit(depthRT, BuiltinRenderTextureType.CameraTarget);


            CommandBufferPool.Release(cmd);

        }
    }

    CustomDepthPass depthPass;
    RTHandle depthRT;

    public Material depthMaterial;
    public Mesh particleMesh;

    public override void Create()
    {
        depthPass = new CustomDepthPass(depthMaterial, particleMesh);

        depthRT = RTHandles.Alloc(
            width: 1920,
            height: 1080,
            colorFormat: GraphicsFormat.R32_SFloat,
            dimension: TextureDimension.Tex2D,
            useDynamicScale: true,
            name: "_ParticleDepthTexture"
        );
        depthRT.rt.wrapMode = TextureWrapMode.Clamp;

    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var myComp = GameObject.FindObjectOfType<ScreenSpaceRenderer>();
        if (myComp == null) return;

        //depthPass.Setup(myComp.cBuffer, myComp.particleCount, myComp.maxVelocity, myComp.radius, depthRT);
        renderer.EnqueuePass(depthPass);
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        depthRT?.Release();
    }
}