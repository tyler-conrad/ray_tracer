import 'dart:io' as io;
import 'dart:typed_data' as td;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:bitmap/bitmap.dart' as bm;
import 'package:flutter/foundation.dart' as f;
import 'package:flutter/material.dart' as m;
import 'package:flutter_spinkit/flutter_spinkit.dart' as sk;

class RenderChunkConfig {
  RenderChunkConfig(
      {required this.coreIndex,
      required this.start,
      required this.numScanLines,
      required this.width,
      required this.height,
      required this.randomDoubles});

  final int coreIndex;
  final int start;
  final int numScanLines;
  final int width;
  final int height;
  final List<double> randomDoubles;
}

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

class Ray {
  Ray({
    required this.origin,
    required this.direction,
  });

  vm.Vector3 origin;
  vm.Vector3 direction;

  vm.Vector3 pointAt(double t) => origin + direction * t;

  void setFrom(Ray other) {
    origin = other.origin;
    direction = other.direction;
  }

  factory Ray.zero() {
    return Ray(
      origin: vm.Vector3.zero(),
      direction: vm.Vector3.zero(),
    );
  }
}

class HitRecord {
  HitRecord({
    required this.t,
    required this.point,
    required this.normal,
    required this.material,
  });

  factory HitRecord.empty() {
    return HitRecord(
      t: 0.0,
      point: vm.Vector3.zero(),
      normal: vm.Vector3.zero(),
      material: Lambertian(albedo: vm.Vector3.zero()),
    );
  }

  double t;
  vm.Vector3 point;
  vm.Vector3 normal;
  Material material;

  void setFrom(HitRecord other) {
    t = other.t;
    point = other.point;
    normal = other.normal;
    material = other.material;
  }
}

abstract class Material {
  bool scatter(
    Ray rayIn,
    HitRecord hit,
    vm.Vector3 attenuation,
    Ray scattered,
  );
}

class Lambertian implements Material {
  Lambertian({required this.albedo});

  final vm.Vector3 albedo;

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

vm.Vector3 reflect(vm.Vector3 v, vm.Vector3 normal) {
  return v - normal * v.dot(normal) * 2.0;
}

class Metal implements Material {
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
    refracted.setFrom((uv - normal * dt) * niOverNt -
        normal * math.pow(discriminant, 0.5).toDouble());
    return true;
  }
  return false;
}

double schlick(double cosine, double refractionIndex) {
  final r = (1.0 - refractionIndex) / (1.0 + refractionIndex);
  final r0 = r * r;
  return r0 + (1.0 - r0) * math.pow(1.0 - cosine, 5.0);
}

class Dielectric implements Material {
  Dielectric({required this.refractionIndex});

  final double refractionIndex;

  @override
  bool scatter(
      Ray rayIn, HitRecord hit, vm.Vector3 attenuation, Ray scattered) {
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

abstract class Hitable {
  bool hit(
    Ray ray,
    double tMin,
    double tMax,
    HitRecord hit,
  );
}

class HitableList implements Hitable {
  HitableList(this.list);

  final List<Hitable> list;

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

class Sphere implements Hitable {
  Sphere(
    this.center,
    this.radius,
    this.material,
  );

  final vm.Vector3 center;
  final double radius;
  final Material material;

  @override
  bool hit(Ray ray, double tMin, double tMax, HitRecord hit) {
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

vm.Vector3 randomPointOnUnitDisk() {
  vm.Vector3 p;
  do {
    final r = vm.Vector3.random();
    r.z = 0.0;
    p = r * 2.0 - vm.Vector3(1.0, 1.0, 0.0);
  } while (p.dot(p) >= 1.0);
  return p;
}

class Camera {
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

    final _w = lookFrom - lookAt;
    final focusDistance = _w.length;

    final w = _w.normalized();
    u = vm.Vector3(0.0, 1.0, 0.0).cross(w).normalized();
    v = w.cross(u);

    lowerLeftCorner = origin -
        u * halfWidth * focusDistance -
        v * halfHeight * focusDistance -
        w * focusDistance;
    horizontal = u * 2.0 * halfWidth * focusDistance;
    vertical = v * 2.0 * halfHeight * focusDistance;
  }

  late final vm.Vector3 lowerLeftCorner;
  late final vm.Vector3 horizontal;
  late final vm.Vector3 vertical;
  late final vm.Vector3 origin;
  late final double lensRadius;
  late final vm.Vector3 u;
  late final vm.Vector3 v;

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
                    albedo: vm.Vector3(0.5 * (1.0 + r()), 0.5 * (1.0 + r()),
                        0.5 * (1.0 + r())),
                    fuzz: 0.5 * rng.nextDouble())),
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

List<List<List<int>>> _renderChunk(RenderChunkConfig config) {
  const int _numAntiAliasingSamples = 32;
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
      for (int s = 0; s < _numAntiAliasingSamples; s++) {
        double u = (i.toDouble() + rng.nextDouble()) / config.width;
        double v = (j.toDouble() + rng.nextDouble()) / config.height;
        Ray ray = camera.getRay(u, v);
        c += color(ray, world, 0);
      }
      c /= _numAntiAliasingSamples.toDouble();
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

class RayTracer extends m.StatefulWidget {
  const RayTracer({m.Key? key}) : super(key: key);

  @override
  m.State<RayTracer> createState() => _RayTracerState();
}

class _RayTracerState extends m.State<RayTracer>
    with m.WidgetsBindingObserver, m.SingleTickerProviderStateMixin {
  final randomDoubles = List.generate(3000, (_index) => rng.nextDouble());

  late final void Function() updater;

  m.Size _screenSize = const m.Size(1.0, 1.0);
  ui.Image? _image;

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
                    _renderChunk,
                    RenderChunkConfig(
                      coreIndex: index,
                      start: index * numScanLinesPerIsolate,
                      numScanLines: numScanLinesPerIsolate + height % numCores,
                      width: width,
                      height: height,
                      randomDoubles: randomDoubles,
                    ))
                : f.compute(
                    _renderChunk,
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
        ? m.Center(
            child: m.Column(
                mainAxisAlignment: m.MainAxisAlignment.center,
                children: const [
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

class RayTracerApp extends m.StatelessWidget {
  const RayTracerApp({m.Key? key}) : super(key: key);

  @override
  m.Widget build(m.BuildContext context) {
    return m.WidgetsApp(
      color: m.Colors.black,
      builder: (context, widget) => const RayTracer(),
    );
  }
}

void main() {
  m.runApp(const RayTracerApp());
}
