using UnityEngine;

public class CameraMovement : MonoBehaviour
{
    public float moveSpeed = 3f;

    public float mouseSensitivity = 300f;

    float yaw;
    float pitch;

    float m_CurrMoveSpeed;

    // Awake is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        Cursor.lockState = CursorLockMode.Locked;
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKey(KeyCode.LeftShift))
        {
            m_CurrMoveSpeed = moveSpeed * 10f;
        }
        else
        {
            m_CurrMoveSpeed = moveSpeed;
        }

        transform.position += transform.right * Input.GetAxis("Horizontal") * m_CurrMoveSpeed * Time.smoothDeltaTime;
        transform.position += transform.forward * Input.GetAxis("Vertical") * m_CurrMoveSpeed * Time.smoothDeltaTime;
        transform.position += transform.up * Input.GetAxis("Custom Vertical") * m_CurrMoveSpeed * Time.smoothDeltaTime;

        // Get mouse input for rotation
        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity * Time.smoothDeltaTime;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity * Time.smoothDeltaTime;

        // Adjust yaw and pitch based on mouse input
        yaw += mouseX;
        pitch -= mouseY;

        pitch = Mathf.Clamp(pitch, -85f, 85f); // Limit pitch to prevent flipping the camera

        // Apply rotation
        transform.rotation = Quaternion.Euler(pitch, yaw, 0f);

    }

}
