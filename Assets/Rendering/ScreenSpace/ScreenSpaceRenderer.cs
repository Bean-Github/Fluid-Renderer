using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using static ComputeHelper;
using static Unity.Burst.Intrinsics.X86.Avx;

public class ScreenSpaceRenderer : MonoBehaviour
{
    public Material particleMaterial;
    public Mesh particleMesh;

    public float maxVelocity = 5.0f;

    public RenderTexture depthRT;
    public Shader depthShader;

    void InitTextures()
    {
        int width = Screen.width;
        int height = Screen.height;

        //ComputeHelper.CreateRenderTexture(ref depthRT, width, height, FilterMode.Bilinear, GraphicsFormat.R32_SFloat, depthMode: DepthMode.Depth16);

        if (depthRT == null)
        {
            depthRT = new RenderTexture(width, height, 16, GraphicsFormat.R32_SFloat);
            depthRT.enableRandomWrite = true;
            depthRT.Create();
        }


    }

    public void RenderParticles(ComputeBuffer particleBuffer, int count, float radius, Bounds bounds)
    {
        InitTextures();

        RenderParams rp = new RenderParams(particleMaterial);
        rp.worldBounds = new Bounds(Vector3.zero, 10000 * Vector3.one); // use tighter bounds
        rp.matProps = new MaterialPropertyBlock();

        rp.matProps.SetFloat("_NumInstances", count);
        rp.matProps.SetBuffer("particles", particleBuffer);

        rp.matProps.SetFloat("scale", radius);

        rp.matProps.SetMatrix("_CameraToWorld", Camera.main.cameraToWorldMatrix);
        rp.matProps.SetMatrix("_CameraInvProjection", Camera.main.projectionMatrix.inverse);

        Graphics.SetRenderTarget(depthRT);

        Graphics.RenderMeshPrimitives(rp, particleMesh, 0, count);

    }

    //public Shader depthShader;

    //CommandBuffer cmd;
    //Material matDepth;

    //ComputeBuffer argsBuffer;

    //void InitTextures()
    //{
    //    int width = Screen.width;
    //    int height = Screen.height;

    //    //ComputeHelper.CreateRenderTexture(ref depthRT, width, height, FilterMode.Bilinear, GraphicsFormat.R32_SFloat, depthMode: DepthMode.Depth16);

    //    if (depthRT == null)
    //    {
    //        depthRT = new RenderTexture(width, height, 16, GraphicsFormat.R8G8B8A8_UNorm);
    //        depthRT.enableRandomWrite = true;
    //        depthRT.Create();
    //    }

    //    if (!matDepth) matDepth = new Material(depthShader);
    //}

    //void RenderCamSetup()
    //{
    //    if (cmd == null)
    //    {
    //        cmd = new();
    //        cmd.name = "Fluid Render Commands";
    //    }

    //    Camera.main.RemoveAllCommandBuffers();
    //    Camera.main.AddCommandBuffer(CameraEvent.AfterEverything, cmd);
    //    Camera.main.depthTextureMode = DepthTextureMode.Depth;
    //}

    //// For DrawMeshInstancedIndirect:
    //// [indexCount, instanceCount, startIndex, baseVertex, startInstance]
    //void CreateArgsBuffer(Mesh mesh, int instanceCount)
    //{
    //    if (argsBuffer != null) argsBuffer.Release();

    //    uint[] args = new uint[5] {
    //    mesh.GetIndexCount(0),
    //    (uint)instanceCount,
    //    mesh.GetIndexStart(0),
    //    mesh.GetBaseVertex(0),
    //    0
    //};

    //    argsBuffer = new ComputeBuffer(1, args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
    //    argsBuffer.SetData(args);
    //}

    //InitTextures();
    //RenderCamSetup();


    //matDepth.SetMatrix("_CameraToWorld", Camera.main.cameraToWorldMatrix);
    //matDepth.SetVector("_ProjectionParams", new Vector4(1, Camera.main.nearClipPlane, Camera.main.farClipPlane, 0));


    //if (cmd == null)
    //{
    //    cmd = new CommandBuffer { name = "Draw Particles To Depth" };
    //    Camera.main.AddCommandBuffer(CameraEvent.AfterEverything, cmd);
    //}

    //cmd.Clear(); // Reset before issuing new commands

    //CreateArgsBuffer(particleMesh, count);

    //matDepth.SetBuffer("particles", particleBuffer);
    //matDepth.SetFloat("_Scale", 0.08f); // or whatever your shader uses

    //// Set your custom depth render target
    //cmd.ClearRenderTarget(true, true, Color.clear); // optional but tidy

    //// Draw particles using indirect draw
    //cmd.DrawMeshInstancedIndirect(
    //    particleMesh,
    //    0,
    //    matDepth,
    //    0,
    //    argsBuffer
    //);



    //public void RenderParticles(ComputeBuffer particleBuffer, int count, Bounds bounds)
    //{
    //    InitTextures();
    //    RenderCamSetup();

    //    matDepth.SetBuffer("particles", particleBuffer);
    //    matDepth.SetFloat("scale", 0.08f);

    //    cmd.SetRenderTarget(depthRT);
    //    cmd.ClearRenderTarget(true, true, Color.clear);

    //    ComputeHelper.CreateArgsBuffer(ref argsBuffer, particleMesh, count);

    //    cmd.DrawMeshInstancedIndirect(particleMesh, 0, matDepth, 0, argsBuffer);


    //    //RenderParams rp = new RenderParams(particleMaterial);
    //    //rp.worldBounds = new Bounds(Vector3.zero, 10000 * Vector3.one); // use tighter bounds
    //    //rp.matProps = new MaterialPropertyBlock();

    //    //rp.matProps.SetFloat("_NumInstances", count);
    //    //rp.matProps.SetBuffer("particles", particleBuffer);

    //    //rp.matProps.SetFloat("maxVelocity", maxVelocity);

    //    //rp.matProps.SetMatrix("_CameraToWorld", Camera.main.cameraToWorldMatrix);
    //    //rp.matProps.SetMatrix("_CameraInvProjection", Camera.main.projectionMatrix.inverse);

    //    //Graphics.SetRenderTarget(depthRT);

    //    //Graphics.RenderMeshPrimitives(rp, particleMesh, 0, count);

    //}
}







//RenderParams rp = new RenderParams(particleMaterial);
//rp.worldBounds = bounds; // use tighter bounds
//rp.matProps = new MaterialPropertyBlock();

//rp.matProps.SetBuffer("particles", particleBuffer);
//rp.matProps.SetFloat("_Radius", radius);

//Graphics.RenderMeshPrimitives(rp, particleMesh, 0, 10);


//using System.Collections.Generic;
//using System.Threading.Tasks;
//using UnityEngine;

//public class ParticleManager : MonoBehaviour
//{
//    [Header("Instancing Settings")]
//    public Mesh particleMesh;
//    public Material particleMaterial;

//    [Header("Simulation Settings")]
//    public Gradient velocityGradient;

//    Matrix4x4[] matrices;
//    Vector4[] colors;

//    Vector3[] positions;

//    //public Particle3D[] particles;

//    MaterialPropertyBlock propertyBlock;

//    int particleCount;
//    float maxVelocity;

//    public void Initialize(int particleCount, float maxVelocity)
//    {
//        matrices = new Matrix4x4[particleCount];
//        colors = new Vector4[particleCount];
//        positions = new Vector3[particleCount];

//        // required to specify to each instance what specific color they will show
//        propertyBlock = new MaterialPropertyBlock();

//        this.particleCount = particleCount;
//        this.maxVelocity = maxVelocity;
//    }

//    public void RenderParticles(Particle3D[] particles)
//    {            
//        for (int i = 0; i < particles.Length; i++) {
//            Vector3 pos = particles[i].position;
//            float speed = particles[i].velocity.magnitude;

//            // we send a 4x4 matrix which defines, postion, rotation and scale
//            matrices[i] = Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one * particles[i].radius);

//            float colorT = speed / maxVelocity;

//            Color c = velocityGradient.Evaluate(colorT);

//            colors[i] = c;
//        }

//        // Apply per-instance colors
//        propertyBlock.SetVectorArray("_BaseColor", colors);

//        // Draw in batches
//        const int batchSize = 1023;
//        Matrix4x4[] batchMatrices = new Matrix4x4[batchSize];

//        for (int i = 0; i < particleCount; i += batchSize)
//        {
//            int count = Mathf.Min(batchSize, particleCount - i);

//            // Copy matrix data for this batch
//            System.Array.Copy(matrices, i, batchMatrices, 0, count);

//            // Create a new property block for this batch
//            var block = new MaterialPropertyBlock();

//            // Copy color data for this batch
//            Vector4[] batchColors = new Vector4[count];
//            System.Array.Copy(colors, i, batchColors, 0, count);

//            // Assign per-instance colors
//            block.SetVectorArray("_BaseColor", batchColors);

//            // Draw the batch
//            Graphics.DrawMeshInstanced(
//                particleMesh,
//                0,
//                particleMaterial,
//                batchMatrices,
//                count,
//                block,
//                UnityEngine.Rendering.ShadowCastingMode.Off,
//                false,
//                0,
//                null,
//                UnityEngine.Rendering.LightProbeUsage.Off
//            );
//        }
//    }

//}


