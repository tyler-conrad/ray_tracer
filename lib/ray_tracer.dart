/// Main library for the ray_tracer project.
///
/// The ray tracer library is responsible for rendering realistic images by
/// simulating the behavior of light rays. It provides various functions and
/// classes for creating and manipulating 3D scenes, generating rays, and
/// calculating intersections with objects in the scene.
library;

import 'dart:io' as io;
import 'dart:typed_data' as td;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' as m;

import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:bitmap/bitmap.dart' as bm;
import 'package:flutter/foundation.dart' as f;
import 'package:flutter_spinkit/flutter_spinkit.dart' as sk;

/// Represents the configuration for rendering a chunk of the output image using
/// isolates to distribute the work.
class RenderChunkConfig {
  RenderChunkConfig({
    required this.coreIndex,
    required this.start,
    required this.numScanLines,
    required this.width,
    required this.height,
    required this.randomDoubles,
  });

  final int coreIndex;
  final int start;
  final int numScanLines;
  final int width;
  final int height;
  final List<double> randomDoubles;
}

/// Random number generator
final rng = math.Random();

vm.Vector3 randomPointOnUnitSphere() {
  vm.Vector3 p;
  do {
    p = vm.Vector3.random(
              rng,
            ) *
            2.0 -
        vm.Vector3.all(1.0);
  } while (p.length2 >= 1.0);
  return p;
}

/// Represents a ray in a 3D space.
///
/// A ray is defined by its origin and direction.
class Ray {
  /// The origin point of the ray.
  vm.Vector3 origin;

  /// The direction of the ray.
  vm.Vector3 direction;

  /// Creates a new instance of the [Ray] class configured with an [origin] and
  /// [direction].
  Ray({
    required this.origin,
    required this.direction,
  });

  /// Calculates a point along the ray at a given distance [t].
  vm.Vector3 pointAt(double t) => origin + direction * t;

  /// Sets the origin and direction of the ray from another ray [other].
  void setFrom(Ray other) {
    origin = other.origin;
    direction = other.direction;
  }

  /// Creates a new instance of the [Ray] class with zero [origin] and
  /// [direction].
  factory Ray.zero() {
    return Ray(
      origin: vm.Vector3.zero(),
      direction: vm.Vector3.zero(),
    );
  }
}

/// Represents a record of a hit in a ray tracing simulation.
class HitRecord {
  /// The distance at which the hit occurred along the ray.
  double t;

  /// The point in 3D space where the hit occurred.
  vm.Vector3 point;

  /// The surface normal at the hit point.
  vm.Vector3 normal;

  /// The material of the object that was hit.
  Material material;

  /// Creates a new instance of [HitRecord].
  ///
  /// [t] is the parameter at which the hit occurred along the ray.
  /// [point] is the point in 3D space where the hit occurred.
  /// [normal] is the surface normal at the hit point.
  /// [material] is the material of the object that was hit.
  HitRecord({
    required this.t,
    required this.point,
    required this.normal,
    required this.material,
  });

  /// Creates an empty instance of [HitRecord].
  ///
  /// An empty [HitRecord] is typically used as a placeholder when no hit occurs.
  factory HitRecord.empty() {
    return HitRecord(
      t: 0.0,
      point: vm.Vector3.zero(),
      normal: vm.Vector3.zero(),
      material: Lambertian(albedo: vm.Vector3.zero()),
    );
  }

  /// Sets the values of this [HitRecord] from another [HitRecord].
  ///
  /// The [other] parameter represents the [HitRecord] from which to copy the values.
  void setFrom(HitRecord other) {
    t = other.t;
    point = other.point;
    normal = other.normal;
    material = other.material;
  }
}

/// Represents a material used in ray tracing.
///
/// This is an abstract class that defines the behavior of materials in a ray
/// tracer. Materials are responsible for scattering rays and determining the
/// attenuation and scattered ray.
abstract class Material {
  /// Scatters an incoming ray off the material.
  bool scatter(
    Ray rayIn,
    HitRecord hit,
    vm.Vector3 attenuation,
    Ray scattered,
  );
}

/// Represents a Lambertian material.
///
/// This material scatters rays in a diffuse manner, with the scattered ray
/// direction determined by adding a random point on a unit sphere to the hit
/// point normal.
class Lambertian implements Material {
  /// Creates a Lambertian material with the given albedo.
  ///
  /// The [albedo] parameter represents the color of the material.
  Lambertian({required this.albedo});

  final vm.Vector3 albedo;

  /// Calculates the scattering of a ray.
  ///
  /// This method calculates the scattering of a given ray based on the hit
  /// record and the albedo. It sets the attenuation vector to the albedo value
  /// and calculates the target vector by adding the hit point, the normal
  /// vector, and a random point on the unit sphere. It sets the scattered ray
  /// by creating a new ray with the hit point as the origin and the direction
  /// as the difference between the target and the hit point. Returns true if
  /// the scattering is successful.
  @override
  bool scatter(
    Ray rayIn,
    HitRecord hit,
    vm.Vector3 attenuation,
    Ray scattered,
  ) {
    attenuation.setFrom(albedo);

    vm.Vector3 target = hit.point + hit.normal + randomPointOnUnitSphere();
    scattered.setFrom(Ray(
      origin: hit.point,
      direction: target - hit.point,
    ));
    return true;
  }
}

/// Calculates the reflection of a vector `v` against a given normal vector.
vm.Vector3 reflect(vm.Vector3 v, vm.Vector3 normal) {
  return v - normal * v.dot(normal) * 2.0;
}

/// Represents a metal material for ray tracing.
class Metal implements Material {
  /// Creates a new [Metal] material with the specified [albedo] and [fuzz].
  Metal({
    required this.albedo,
    required double fuzz,
  }) {
    if (fuzz < _maxFuzz) {
      _fuzz = fuzz;
    } else {
      _fuzz = _maxFuzz;
    }
  }

  static const _maxFuzz = 1.0;

  final vm.Vector3 albedo;
  late final double _fuzz;

  /// Calculates the scattered ray after a ray hits an object.
  ///
  /// [rayIn] is the incoming ray. [hit] contains information about the hit
  /// point on the object. [attenuation] is the attenuation of the scattered
  /// ray. [scattered] is the resulting scattered ray.
  ///
  /// Returns `true` if the scattered ray is in the same direction as the
  /// surface normal, `false` otherwise.
  @override
  bool scatter(
    Ray rayIn,
    HitRecord hit,
    vm.Vector3 attenuation,
    Ray scattered,
  ) {
    var reflected = reflect(
      rayIn.direction.normalized(),
      hit.normal,
    );
    scattered.setFrom(Ray(
      origin: hit.point,
      direction: reflected + randomPointOnUnitSphere() * _fuzz,
    ));
    attenuation.setFrom(albedo);
    return scattered.direction.dot(hit.normal) > 0.0;
  }
}

/// Calculates the refraction of a vector based on the given parameters.
///
/// The function takes in a vector [v], a [normal], a refractive index ratio [niOverNt],
/// and a vector [refracted] to store the result. It returns a boolean value indicating whether
/// refraction occurred successfully or not.
bool refract(
  vm.Vector3 v,
  vm.Vector3 normal,
  double niOverNt,
  vm.Vector3 refracted,
) {
  final uv = v.normalized();
  final dt = uv.dot(normal);
  final discriminant = 1.0 - niOverNt * (1.0 - dt * dt);

  if (discriminant > 0.0) {
    refracted.setFrom(
      (uv - normal * dt) * niOverNt -
          normal * math.pow(discriminant, 0.5).toDouble(),
    );
    return true;
  }
  return false;
}

/// Calculates the Schlick approximation for the reflection coefficient.
///
/// The Schlick approximation is used to estimate the reflection coefficient
/// of a material based on the angle of incidence and the refractive index.
double schlick(double cosine, double refractionIndex) {
  final r = (1.0 - refractionIndex) / (1.0 + refractionIndex);
  final r0 = r * r;
  return r0 + (1.0 - r0) * math.pow(1.0 - cosine, 5.0);
}

/// Represents a dielectric material.
///
/// Dielectric materials are used in ray tracing to simulate transparent objects.
class Dielectric implements Material {
  Dielectric({required this.refractionIndex});

  final double refractionIndex;

  /// Calculates the scattering of a ray when it hits a surface.
  ///
  /// This method takes in a [rayIn] representing the incident ray, a [hit] object
  /// containing information about the intersection point, an [attenuation] vector
  /// to store the attenuation of the ray, and a [scattered] ray object to store
  /// the scattered ray.
  ///
  /// The method first calculates the outward normal and the reflected vector based
  /// on the incident ray and the surface normal. It then determines the refracted
  /// vector and the reflection probability. Finally, it sets the scattered ray
  /// based on the reflection probability and returns true.
  @override
  bool scatter(
    Ray rayIn,
    HitRecord hit,
    vm.Vector3 attenuation,
    Ray scattered,
  ) {
    final vm.Vector3 outwardNormal;
    final vm.Vector3 reflected = reflect(rayIn.direction, hit.normal);
    final double niOverNt;
    attenuation.setFrom(vm.Vector3(
      1.0,
      1.0,
      1.0,
    ));
    final vm.Vector3 refracted = vm.Vector3.zero();
    double reflectProb;
    double cosine;

    if (rayIn.direction.dot(hit.normal) > 0.0) {
      outwardNormal = -hit.normal;
      niOverNt = refractionIndex;
      cosine = refractionIndex *
          rayIn.direction.dot(hit.normal) /
          rayIn.direction.length;
    } else {
      outwardNormal = hit.normal;
      niOverNt = 1.0 / refractionIndex;
      cosine = -rayIn.direction.dot(hit.normal) / rayIn.direction.length2;
    }

    if (refract(
      rayIn.direction,
      outwardNormal,
      niOverNt,
      refracted,
    )) {
      reflectProb = schlick(cosine, refractionIndex);
    } else {
      reflectProb = 0.1;
    }

    if (rng.nextDouble() < reflectProb) {
      scattered.setFrom(Ray(
        origin: hit.point,
        direction: reflected,
      ));
    } else {
      scattered.setFrom(Ray(
        origin: hit.point,
        direction: refracted,
      ));
    }
    return true;
  }
}

/// An abstract class representing a hitable object.
abstract class Hitable {
  /// Determines if a [ray] [hit]s an object.
  bool hit(
    Ray ray,
    double tMin,
    double tMax,
    HitRecord hit,
  );
}

/// Represents a list of objects that can be hit.
class HitableList implements Hitable {
  HitableList(this.list);

  final List<Hitable> list;

  /// Determines if a ray hits any objects in the scene.
  ///
  /// This method checks if a given [ray] intersects with any objects in the scene.
  /// It iterates through the list of objects and updates the [hit] parameter with
  /// the closest intersection information. The method returns `true` if any object
  /// is hit, and `false` otherwise.
  ///
  /// The [tMin] and [tMax] parameters define the range of valid intersection distances.
  /// The [hit] parameter is an instance of the [HitRecord] class, which is used to store
  /// information about the closest intersection. If an intersection is found, the [hit] parameter
  /// is updated with the intersection details.
  @override
  bool hit(
    Ray ray,
    double tMin,
    double tMax,
    HitRecord hit,
  ) {
    HitRecord tempRecord = HitRecord.empty();
    bool hitAnything = false;
    double closestSoFar = tMax;
    for (int i = 0; i < list.length; i++) {
      if (list[i].hit(
        ray,
        tMin,
        closestSoFar,
        tempRecord,
      )) {
        hitAnything = true;
        closestSoFar = tempRecord.t;
        hit.setFrom(tempRecord);
      }
    }
    return hitAnything;
  }
}

/// Represents a sphere.
class Sphere implements Hitable {
  /// Creates a [Sphere] object with the specified [center], [radius], and
  /// [material].
  Sphere(
    this.center,
    this.radius,
    this.material,
  );

  final vm.Vector3 center;
  final double radius;
  final Material material;

  /// Checks if a ray intersects with the object.
  ///
  /// The intersection calculation is based on the ray's origin, direction, and
  /// the object's center and radius. It uses the quadratic formula to solve for
  /// the intersection points. If there are multiple intersection points, the
  /// closest one within the range is selected.
  @override
  bool hit(
    Ray ray,
    double tMin,
    double tMax,
    HitRecord hit,
  ) {
    final oc = ray.origin - center;
    final a = ray.direction.dot(ray.direction);
    final b = 2.0 * oc.dot(ray.direction);
    final c = oc.dot(oc) - radius * radius;
    final discriminant = b * b - 4.0 * a * c;
    if (discriminant > 0.0) {
      double temp = (-b - math.pow(discriminant, 0.5)) / (2.0 * a);
      if (temp > tMin && temp < tMax) {
        hit.t = temp;
        hit.point = ray.pointAt(hit.t);
        hit.normal = (hit.point - center) / radius;
        hit.material = material;
        return true;
      }
      temp = (-b + math.pow(discriminant, 0.5)) / (2.0 * a);
      if (temp > tMin && temp < tMax) {
        hit.t = temp;
        hit.point = ray.pointAt(hit.t);
        hit.normal = (hit.point - center) / radius;
        hit.material = material;
        return true;
      }
    }
    return false;
  }
}

/// Generates a random point on a unit disk.
vm.Vector3 randomPointOnUnitDisk() {
  vm.Vector3 p;
  do {
    final r = vm.Vector3.random();
    r.z = 0.0;
    p = r * 2.0 - vm.Vector3(1.0, 1.0, 0.0);
  } while (p.dot(p) >= 1.0);
  return p;
}

/// Represents a camera.
class Camera {
  late final vm.Vector3 lowerLeftCorner;
  late final vm.Vector3 horizontal;
  late final vm.Vector3 vertical;
  late final vm.Vector3 origin;
  late final double lensRadius;
  late final vm.Vector3 u;
  late final vm.Vector3 v;

  /// Constructs a [Camera] object with the specified parameters.
  ///
  /// - [width] of the camera viewport.
  /// - [height] of the camera viewport.
  /// - [verticalFov] vertical field of view in degrees.
  /// - [lookFrom] position of the camera.
  /// - [lookAt] target position the camera is looking at.
  /// - [aperture] size of the camera aperture.
  Camera({
    required int width,
    required int height,
    required double verticalFov,
    required vm.Vector3 lookFrom,
    required vm.Vector3 lookAt,
    required double aperture,
  }) {
    lensRadius = aperture * 0.5;

    final aspect = width / height;
    final theta = verticalFov * (math.pi / 180.0);

    final halfHeight = math.tan(theta * 0.5);
    final halfWidth = aspect * halfHeight;

    origin = lookFrom;

    vm.Vector3 w = lookFrom - lookAt;
    final focusDistance = w.length;

    w = w.normalized();
    u = vm.Vector3(0.0, 1.0, 0.0).cross(w).normalized();
    v = w.cross(u);

    lowerLeftCorner = origin -
        u * halfWidth * focusDistance -
        v * halfHeight * focusDistance -
        w * focusDistance;
    horizontal = u * 2.0 * halfWidth * focusDistance;
    vertical = v * 2.0 * halfHeight * focusDistance;
  }

  /// Returns a [Ray] object based on the given parameters.
  ///
  /// The [s] parameter represents the horizontal coordinate of the ray in the viewport,
  /// while the [t] parameter represents the vertical coordinate of the ray in the viewport.
  ///
  /// Calculates the offset of the ray based on a random point on the unit disk
  /// multiplied by the lens radius. It then constructs a [Ray] object with the calculated origin
  /// and direction.
  Ray getRay(double s, double t) {
    final rd = randomPointOnUnitDisk() * lensRadius;
    vm.Vector3 offset = u * rd.x + v * rd.y;
    return Ray(
      origin: origin + offset,
      direction:
          lowerLeftCorner + horizontal * s + vertical * t - origin - offset,
    );
  }
}

/// Calculates the color of a ray in the scene.
///
/// This function takes a [Ray] and a [Hitable] object representing the scene,
/// along with the current depth of recursion. It returns a [vm.Vector3] object
/// representing the color of the ray.
///
/// The function first checks if the ray intersects with any object in the
/// scene. If an intersection is found, it calculates the attenuation and
/// scattered ray using the hit record and the material of the object. If the
/// depth is less than 32 and the material scatters the ray, the function
/// recursively calls itself with the scattered ray and increments the depth.
/// The resulting color is then multiplied by the attenuation and returned.
///
/// If no intersection is found, the function calculates the background color
/// based on the direction of the ray. The resulting color is a linear
/// interpolation between white and light blue based on the y-component of the
/// ray direction.
/// - [ray] ray to calculate the color for.
/// - [world] scene represented by a [Hitable] object.
/// - [depth] current depth of recursion.
vm.Vector3 color(
  Ray ray,
  Hitable world,
  int depth,
) {
  HitRecord hit = HitRecord.empty();
  if (world.hit(ray, 0.001, double.maxFinite, hit)) {
    vm.Vector3 attenuation = vm.Vector3.zero();
    Ray scattered = Ray.zero();
    if (depth < 32 &&
        hit.material.scatter(
          ray,
          hit,
          attenuation,
          scattered,
        )) {
      final a = vm.Vector3.zero();
      a.setFrom(attenuation);
      a.multiply(color(
        scattered,
        world,
        depth + 1,
      ));
      return a;
    }
    return vm.Vector3.zero();
  }
  final t = (ray.direction.normalized().y + 1.0) * 0.5;
  return vm.Vector3(1.0, 1.0, 1.0) * (1.0 - t) + vm.Vector3(0.5, 0.7, 1.0) * t;
}

/// Creates a scene of spheres with different materials.
Hitable scene(Iterable<double> random) {
  const sceneSize = 5;

  final randomIterator = random.iterator;
  double r() {
    randomIterator.moveNext();
    return randomIterator.current;
  }

  final sphereList = <Hitable>[];

  for (int a = -(sceneSize - 1); a < sceneSize; a++) {
    for (int b = -(sceneSize - 1); b < sceneSize; b++) {
      final chooseMaterial = r();
      final center = vm.Vector3(
        a + 0.9 * r(),
        0.2,
        b + 0.9 * r(),
      );
      if ((center - vm.Vector3(4.0, 0.2, 0.0)).length > 0.9) {
        if (chooseMaterial < 0.8) {
          sphereList.add(Sphere(
            center,
            0.2,
            Lambertian(
                albedo: vm.Vector3(
              r() * r(),
              r() * r(),
              r() * r(),
            )),
          ));
        } else if (chooseMaterial < 0.95) {
          sphereList.add(
            Sphere(
              center,
              0.2,
              Metal(
                albedo: vm.Vector3(
                    0.5 * (1.0 + r()), 0.5 * (1.0 + r()), 0.5 * (1.0 + r())),
                fuzz: 0.5 * rng.nextDouble(),
              ),
            ),
          );
        } else {
          sphereList.add(Sphere(
            center,
            0.2,
            Dielectric(refractionIndex: 1.5),
          ));
        }
      }
    }
  }

  sphereList.add(Sphere(vm.Vector3(0.0, -1000.0, 0.0), 1000,
      Lambertian(albedo: vm.Vector3(0.5, 0.5, 0.5))));

  sphereList.add(Sphere(
    vm.Vector3(0.0, 1.0, -1.0),
    1.0,
    Dielectric(refractionIndex: 1.5),
  ));

  sphereList.add(Sphere(
    vm.Vector3(-3.0, 1.0, -1.0),
    1.0,
    Lambertian(albedo: vm.Vector3(0.4, 0.2, 0.1)),
  ));

  sphereList.add(
    Sphere(vm.Vector3(3.0, 1.0, -1.0), 1.0,
        Metal(albedo: vm.Vector3(0.7, 0.6, 0.5), fuzz: 0.0)),
  );

  return HitableList(sphereList);
}

/// Renders a chunk of the scene based on the provided [config].
///
/// The rendering process includes anti-aliasing and gamma correction.
List<List<List<int>>> renderChunk(RenderChunkConfig config) {
  const int numAntiAliasingSamples = 32;
  const byteSize = 255.99;

  final world = scene(config.randomDoubles);

  final lookFrom = vm.Vector3(4.0, 4.0, -8.0);
  final lookAt = vm.Vector3(0.0, 1.0, -1.0);

  final camera = Camera(
    width: config.width,
    height: config.height,
    verticalFov: 65.0,
    lookFrom: lookFrom,
    lookAt: lookAt,
    aperture: 0.5,
  );

  return List.generate(
    config.numScanLines,
    (y) => List.generate(config.width, (x) {
      final j = (config.height) - config.start - y;
      final i = x;

      vm.Vector3 c = vm.Vector3.zero();
      for (int s = 0; s < numAntiAliasingSamples; s++) {
        double u = (i.toDouble() + rng.nextDouble()) / config.width;
        double v = (j.toDouble() + rng.nextDouble()) / config.height;
        Ray ray = camera.getRay(u, v);
        c += color(ray, world, 0);
      }
      c /= numAntiAliasingSamples.toDouble();
      final gammaCorrected = vm.Vector3(
        math.pow(c.r, 0.5).toDouble(),
        math.pow(c.g, 0.5).toDouble(),
        math.pow(c.b, 0.5).toDouble(),
      );

      int ir = (byteSize * gammaCorrected.r).toInt();
      int ig = (byteSize * gammaCorrected.g).toInt();
      int ib = (byteSize * gammaCorrected.b).toInt();

      return [
        ir,
        ig,
        ib,
        255,
      ];
    }),
  );
}

/// A [m.Widget] used to render a ray traced scene.
class RayTracer extends m.StatefulWidget {
  const RayTracer({super.key});

  @override
  m.State<RayTracer> createState() => _RayTracerState();
}

class _RayTracerState extends m.State<RayTracer>
    with m.WidgetsBindingObserver, m.SingleTickerProviderStateMixin {
  final randomDoubles = List.generate(3000, (index) => rng.nextDouble());

  late final void Function() updater;

  m.Size _screenSize = const m.Size(1.0, 1.0);
  ui.Image? _image;

  /// Rebuilds the bitmap based on the given screen size.
  ///
  /// This method takes the [screenSize] as input and returns a [Future] of
  /// [bm.Bitmap]. It calculates the width and height of the bitmap based on the
  /// ceiling values of the screen size. It also determines the number of cores
  /// available on the platform using [io.Platform.numberOfProcessors]. The
  /// number of scan lines per isolate is calculated by dividing the height of
  /// the screen by the number of cores. The method then generates a list of
  /// futures using [Future.wait] and [List.generate] to render each chunk of
  /// the bitmap. Each chunk is rendered using the [renderChunk] method and
  /// [RenderChunkConfig] parameters. The rendered chunks are then flattened and
  /// converted into a single list using [List.expand] and [Iterable.toList].
  /// Finally, a [bm.Bitmap] is created from the flattened list and returned as
  /// the result.
  Future<bm.Bitmap> _rebuildBitmap(m.Size screenSize) async {
    final width = screenSize.width.ceil();
    final height = screenSize.height.ceil();
    var numCores = io.Platform.numberOfProcessors;
    final numScanLinesPerIsolate = screenSize.height ~/ numCores;

    return bm.Bitmap.fromHeadless(
      width,
      height,
      td.Uint8List.fromList(
        (await Future.wait(
          List.generate(
            numCores,
            (index) => index == numCores - 1
                ? f.compute(
                    renderChunk,
                    RenderChunkConfig(
                      coreIndex: index,
                      start: index * numScanLinesPerIsolate,
                      numScanLines: numScanLinesPerIsolate + height % numCores,
                      width: width,
                      height: height,
                      randomDoubles: randomDoubles,
                    ))
                : f.compute(
                    renderChunk,
                    RenderChunkConfig(
                      coreIndex: index,
                      start: index * numScanLinesPerIsolate,
                      numScanLines: numScanLinesPerIsolate,
                      width: width,
                      height: height,
                      randomDoubles: randomDoubles,
                    ),
                  ),
          ),
        ))
            .expand((e) => e)
            .expand((e) => e)
            .expand((e) => e)
            .toList(),
      ),
    );
  }

  /// Returns a function that updates the build asynchronously.
  ///
  /// Returns a function that can be used to trigger a rebuild of the bitmap
  /// image. It checks if a rebuild is already in progress by checking the
  /// `rebuilding` flag. If a rebuild is not in progress, it sets the
  /// `rebuilding` flag to `true`, awaits the result of
  /// `_rebuildBitmap(_screenSize).buildImage()`, assigns the result to
  /// `_image`, calls `setState()` to update the UI, and finally sets the
  /// `rebuilding` flag back to `false`.
  Future<void> Function() buildUpdater() {
    bool rebuilding = false;
    return () async {
      if (!rebuilding) {
        rebuilding = true;
        _image = await (await _rebuildBitmap(_screenSize)).buildImage();
        setState(() {});
        rebuilding = false;
      }
    };
  }

  @override
  void initState() {
    super.initState();
    m.WidgetsBinding.instance.addObserver(this);
    updater = buildUpdater();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = m.MediaQuery.of(context).size;
    updater();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _screenSize = m.WidgetsBinding.instance.window.physicalSize;
    updater();
  }

  @override
  m.Widget build(m.BuildContext context) {
    return _image == null
        ? const m.Center(
            child: m.Column(
                mainAxisAlignment: m.MainAxisAlignment.center,
                children: [
                m.Text('Rendering...'),
                m.SizedBox(height: 16.0),
                sk.SpinKitFadingCircle(color: m.Colors.white),
              ]))
        : m.RawImage(
            width: _screenSize.width,
            height: _screenSize.height,
            fit: m.BoxFit.cover,
            image: _image,
          );
  }
}

/// A Flutter application that implements a ray tracer.
///
/// This application creates a ray tracer app using the Flutter framework. It
/// renders a scene using ray tracing techniques. The [build] method returns a
/// [m.WidgetsApp] widget with a black background color. The [RayTracer] widget
/// is the main content of the app.
class RayTracerApp extends m.StatelessWidget {
  const RayTracerApp({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    return m.WidgetsApp(
      color: m.Colors.black,
      builder: (context, widget) => const RayTracer(),
    );
  }
}
