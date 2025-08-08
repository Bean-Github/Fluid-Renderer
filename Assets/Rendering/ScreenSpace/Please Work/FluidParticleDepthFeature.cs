using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using static UnityEngine.XR.XRDisplaySubsystem;

public class FluidParticleDepthFeature : ScriptableRendererFeature
{
    class ParticleDepthPass : ScriptableRenderPass
    {
        public Material particleMaterial;
        public Mesh particleMesh;
        public ComputeBuffer particleBuffer;
        public int instanceCount;
        public float maxVelocity;
        public float radius;

        public RenderTexture depthRT;
        private string profilerTag = "Render Particle Depth";

        private RTHandle m_CameraColorTarget;

        public ParticleDepthPass()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingSkybox; // or BeforeRenderingOpaques depending


        }

        RTHandle depthHandle;

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            if (depthRT == null || !depthRT.IsCreated())
            {
                depthRT = new RenderTexture(cameraTextureDescriptor.width, cameraTextureDescriptor.height, 0, GraphicsFormat.R32_SFloat);
                depthRT.enableRandomWrite = true;
                depthRT.Create();
            }

            depthHandle = RTHandles.Alloc(depthRT);

            ConfigureTarget(depthHandle);
            ConfigureClear(ClearFlag.All, Color.clear);
        }


        // gets the values from the renderer feature
        public void SetTarget(RTHandle colorHandle)
        {
            m_CameraColorTarget = colorHandle;
        }

        ComputeBuffer argsBuffer;

        void CreateArgsBuffer(Mesh mesh, int instanceCount)
        {
            if (argsBuffer != null) argsBuffer.Release();

            uint[] args = new uint[5] {
            mesh.GetIndexCount(0),
            (uint)instanceCount,
            mesh.GetIndexStart(0),
            mesh.GetBaseVertex(0),
            0
        };

            argsBuffer = new ComputeBuffer(1, args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
            argsBuffer.SetData(args);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (particleMaterial == null || particleMesh == null || particleBuffer == null) return;

            particleMaterial.SetBuffer("particles", particleBuffer);

            particleMaterial.SetFloat("scale", radius);

            var cmd = CommandBufferPool.Get(profilerTag);

            cmd.SetRenderTarget(depthRT);

            CreateArgsBuffer(particleMesh, instanceCount);

            cmd.DrawMeshInstancedProcedural(
                particleMesh,
                0,
                particleMaterial,
                0,
                instanceCount
            );

            //Graphics.SetRenderTarget(depthHandle);
            //Graphics.RenderMeshPrimitives(rp, particleMesh, 0, instanceCount);

            Blitter.BlitCameraTexture(cmd, depthHandle, m_CameraColorTarget, particleMaterial, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void FrameCleanup(CommandBuffer cmd)
        {
            // Optional cleanup if needed
        }
    }

    ParticleDepthPass particlePass;

    [System.Serializable]
    public class ParticleDepthSettings
    {
        public Material particleMaterial;
        public Mesh particleMesh;
        public float radius = 0.05f;
        public float maxVelocity = 5f;
    }

    public ParticleDepthSettings settings = new ParticleDepthSettings();

    public ComputeBuffer particleBuffer;
    public int instanceCount = 0;

    public RenderTexture depthTexture => particlePass.depthRT;

    public override void Create()
    {
        particlePass = new ParticleDepthPass
        {
            particleMaterial = settings.particleMaterial,
            particleMesh = settings.particleMesh,
            maxVelocity = settings.maxVelocity,
            radius = settings.radius,
            particleBuffer = BlitSettingsFeeder.blitSettingsStatic.fluidRenderer.particleBuffer,
            instanceCount = BlitSettingsFeeder.blitSettingsStatic.fluidRenderer.particleCount
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // Update buffer + count dynamically if needed
        particlePass.particleBuffer = particleBuffer;
        particlePass.instanceCount = instanceCount;

        renderer.EnqueuePass(particlePass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer,
                                        in RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            // Calling ConfigureInput with the ScriptableRenderPassInput.Color argument
            // ensures that the opaque texture is available to the Render Pass.
            particlePass.ConfigureInput(ScriptableRenderPassInput.Color);

            // IMPORTANT: Set the VALUES for the render pass
            particlePass.SetTarget(renderer.cameraColorTargetHandle);
        }
    }
}
