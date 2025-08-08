using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ParticleDepthRenderFeature : ScriptableRendererFeature
{
    class DepthPass : ScriptableRenderPass
    {
        private Material material;
        private Mesh mesh;
        private ComputeBuffer particleBuffer;
        private int instanceCount;

        public DepthPass(Material mat, Mesh quadMesh, ComputeBuffer buffer, int count)
        {
            material = mat;
            mesh = quadMesh;
            particleBuffer = buffer;
            instanceCount = count;

            renderPassEvent = RenderPassEvent.AfterRenderingPrePasses; // BEFORE opaque
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (material == null || mesh == null) return;

            CommandBuffer cmd = CommandBufferPool.Get("Particle Depth");

            material.SetBuffer("particles", particleBuffer);
            material.SetFloat("scale", 0.16f);
            Matrix4x4[] matrices = new Matrix4x4[instanceCount];
            for (int i = 0; i < instanceCount; i++)
                matrices[i] = Matrix4x4.identity;

            cmd.DrawMeshInstanced(mesh, 0, material, 0, matrices, instanceCount);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public Material depthMaterial;
    public Mesh quadMesh;
    public ComputeBuffer particleBuffer;
    public int instanceCount;

    DepthPass pass;

    public override void Create()
    {
        particleBuffer = BlitSettingsFeeder.GetBlitSettings().fluidRenderer.particleBuffer;
        pass = new DepthPass(depthMaterial, quadMesh, particleBuffer, instanceCount);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }
}
