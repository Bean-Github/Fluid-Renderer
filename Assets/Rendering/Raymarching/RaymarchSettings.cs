using UnityEngine;

public class RaymarchSettings : BlitSettings
{
    // key
    [Range(0.01f, 1f)]
    public float stepSize = 0.1f; // default step size, can be adjusted

    [Range(0.01f, 7f)]
    public float lightStepSize = 0.2f; // step size for lighting calculations

    [Range(0.0f, 0.1f)]
    public float densityMultiplier = 1.0f;

    [Range(0.01f, 4.0f)]
    public float indexOfRefraction = 1.33f;

    // lighting
    public int numRefractions = 2;

    public Vector3 scatteringCoefficients = Vector3.one;


    // misc
    public float volumeValueOffset = 150;

}
