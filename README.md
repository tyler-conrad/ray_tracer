# ray_tracer

A Flutter application that implements a simple ray tracer based on the tutorial
[Ray Tracing in One Weekend](https://raytracing.github.io/). The application
leverages the [vector_math](https://pub.dev/packages/vector_math) and
[bitmap](https://pub.dev/packages/bitmap) packages. Rendering is parallelized
based on the number of available CPU cores.

![](screenshot.png)

## Features
- **Ray Tracing**: Simulates the behavior of light rays to render realistic
  images.
- **Parallel Rendering**: Utilizes isolates to distribute rendering tasks.
- **Materials**: Supports different materials like Lambertian, Metal, and
  Dielectric.

## Code Overview
- **RenderChunkConfig**: Configuration for rendering a chunk of the output image
  using isolates.
- **Ray**: Represents a ray in 3D space.
- **HitRecord**: Records details of a hit in the ray tracing simulation.
- **Material**: Abstract class defining the behavior of materials in the ray
  tracer.
- **Lambertian, Metal, Dielectric**: Concrete implementations of different
  materials.
- **Hitable**: Abstract class for objects that can be hit by rays.
- **HitableList, Sphere**: Implementations of hitable objects.
- **Camera**: Represents the camera in the scene.
- **color**: Function to calculate the color of a ray in the scene.
- **scene**: Function to create a scene of spheres with different materials.
- **renderChunk**: Function to render a chunk of the scene.
- **RayTracer**: Flutter widget to render the ray traced scene.
- **RayTracerApp**: Main Flutter application class.

## Tested on
**Platform:**
- macOS Sonoma 14.6.1
**Flutter:**
- Flutter 3.24.0 • channel stable • https://github.com/flutter/flutter.git
- Framework • revision 80c2e84975 (2 weeks ago) • 2024-07-30 23:06:49 +0700
- Engine • revision b8800d88be
- Tools • Dart 3.5.0 • DevTools 2.37.2