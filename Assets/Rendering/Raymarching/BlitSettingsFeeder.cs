using Unity.VisualScripting;
using UnityEngine;

[RequireComponent(typeof(BlitSettings))]
public class BlitSettingsFeeder : MonoBehaviour
{
    // scene values
    //public BoxCollider m_BoxCollider;


    // static values

    //public static BoxCollider boxCollider;

    // TODO: REPLACE WITH BLITSETTINGS

    [HideInInspector]
    public BlitSettings m_BlitSettings;

    public static BlitSettings blitSettingsStatic;

    #region Singleton Implementation
    // Static reference to the single instance of the GameManager
    public static BlitSettingsFeeder Instance { get; private set; }
        
    private void Awake()
    {
        // If an instance already exists and it's not this one, destroy this duplicate
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }

        // Assign this instance as the singleton
        Instance = this;

        m_BlitSettings = this.GetComponent<BlitSettings>();

        // Optional: Keep the singleton alive across scene loads
        DontDestroyOnLoad(gameObject);
    }
    #endregion


    void Start()
    {
        // Ensure static values are set when the script is enabled
        SetStaticValues();
    }

    [ContextMenu("Set Static Values")]
    public void SetStaticValues()
    {
        blitSettingsStatic = m_BlitSettings;

    }


    public static BlitSettings GetFluidRenderer()
    {
        if (blitSettingsStatic == null)
        {
            Debug.LogWarning("FluidRenderer3DCombined is not set in BlitSettingsFeeder. Please assign it in the scene.");
        }
        return blitSettingsStatic;
    }


}




