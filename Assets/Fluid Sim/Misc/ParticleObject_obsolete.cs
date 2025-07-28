//using UnityEngine;

//public class ParticleObject : MonoBehaviour
//{
//    public MeshRenderer meshRenderer;

//    public Gradient gradient;
//    public float maxVelocity;

//    public Vector3 vel;
//    public Vector3 pos;

//    float colorT;

//    public float radius;

//    public void InitializeParticle(Particle3D particle)
//    {
//        radius = particle.radius;
//        transform.localScale = Vector3.one * particle.radius;
//    }

//    public void SetParticle(Particle3D particle)
//    {
//        if (particle.position.magnitude >= 10000.0f)
//            return;

//        pos = particle.position;
//        vel = particle.velocity;

//        colorT = vel.magnitude / maxVelocity;

//        color = gradient.Evaluate(colorT);
//    }

//    public Color color;

//}

