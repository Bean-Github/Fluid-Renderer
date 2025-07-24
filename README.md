# Smoothed Particle Hydrodynamics - 3D Newtonian Fluid Simulation (Unity)

This project implements a real-time fluid simulation using Smoothed Particle Hydrodynamics (SPH) run on the GPU through compute shaders in Unity.
Designed for high-performance particle-based fluid simulation
Complete with physically-based reflection, refraction, spray, foam, and bubbles.

The system includes two rendering approaches:

### 1. Screen Space Fluid Rendering
Particles are rendered into a depth and thickness buffer, and fluid surfaces are reconstructed in screen space. 
Optimized for performance and suitable for interactive applications or games requiring fast visual feedback with reasonable fluid appearance.

### 2. Raymarching-Based Fluid Rendering
A volumetric rendering method where rays are cast and marched through the fluid volume for realistic lighting, depth, and shading. 
This approach provides more realistic lighting, depth, and shading, making it ideal for cinematic visuals or applications requiring higher visual fidelity.

### Other Features
- Bitonic Sort implementation to optimize spatial hashed cell lookup algorithms
- Viscosity, Pressure, Incompressibility, Snell's Law, and Beer's Law
- Deferred screen space reconstruction with depth-aware blending
- Raymarching pass with density sampling, light attenuation, and environment lighting
