using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

public class ParticleManager : MonoBehaviour
{
    [Header("Instancing Settings")]
    public Mesh particleMesh;
    public Material particleMaterial;

    [Header("Simulation Settings")]
    public Gradient velocityGradient;

    Matrix4x4[] matrices;
    Vector4[] colors;

    Vector3[] positions;

    //public Particle3D[] particles;

    MaterialPropertyBlock propertyBlock;

    int particleCount;
    float maxVelocity;

    public void Initialize(int particleCount, float maxVelocity)
    {
        matrices = new Matrix4x4[particleCount];
        colors = new Vector4[particleCount];
        positions = new Vector3[particleCount];

        // required to specify to each instance what specific color they will show
        propertyBlock = new MaterialPropertyBlock();

        this.particleCount = particleCount;
        this.maxVelocity = maxVelocity;
    }

    public void RenderParticles(Particle3D[] particles)
    {            
        for (int i = 0; i < particles.Length; i++) {
            Vector3 pos = particles[i].position;
            float speed = particles[i].velocity.magnitude;

            // we send a 4x4 matrix which defines, postion, rotation and scale
            matrices[i] = Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one * particles[i].radius);

            float colorT = speed / maxVelocity;

            Color c = velocityGradient.Evaluate(colorT);

            colors[i] = c;
        }

        // Apply per-instance colors
        propertyBlock.SetVectorArray("_BaseColor", colors);

        // Draw in batches
        const int batchSize = 1023;
        Matrix4x4[] batchMatrices = new Matrix4x4[batchSize];

        for (int i = 0; i < particleCount; i += batchSize)
        {
            int count = Mathf.Min(batchSize, particleCount - i);

            // Copy matrix data for this batch
            System.Array.Copy(matrices, i, batchMatrices, 0, count);

            // Create a new property block for this batch
            var block = new MaterialPropertyBlock();

            // Copy color data for this batch
            Vector4[] batchColors = new Vector4[count];
            System.Array.Copy(colors, i, batchColors, 0, count);

            // Assign per-instance colors
            block.SetVectorArray("_BaseColor", batchColors);

            // Draw the batch
            Graphics.DrawMeshInstanced(
                particleMesh,
                0,
                particleMaterial,
                batchMatrices,
                count,
                block,
                UnityEngine.Rendering.ShadowCastingMode.Off,
                false,
                0,
                null,
                UnityEngine.Rendering.LightProbeUsage.Off
            );
        }
    }

}