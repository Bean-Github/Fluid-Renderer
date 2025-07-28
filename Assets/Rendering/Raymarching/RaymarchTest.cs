using UnityEngine;

//[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class RaymarchTest : MonoBehaviour
{
    //public Shader shader;
    public Material material;


    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        
    }


    private void Update()
    {
        SetValues();
    }


    void SetValues()
    {
        var cam = Camera.main;

        //Shader.SetGlobalMatrix("_CameraToWorld", cam.cameraToWorldMatrix);
        Shader.SetGlobalMatrix("_CameraInverseProjection", cam.projectionMatrix.inverse);
        Shader.SetGlobalMatrix("_ObjectToWorld", transform.localToWorldMatrix);

        var light = RenderSettings.sun;
        Shader.SetGlobalVector("_SunDirection", transform.forward);
    }

}
