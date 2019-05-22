import 'dart:math' as math;
import 'dart:core';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flame/animation.dart' as FlameAnimation;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(MyGame().widget);

class Screen {
  double x;
  double y;
  double width;
  double scale;
}

class Camera {
  double x;
  double y;
  double z;
}

class RoadSegmentPoint {
  double worldX;
  double worldY;
  double worldZ;
  Screen screen;
  Camera camera;

  RoadSegmentPoint(this.worldX, this.worldY, this.worldZ, this.screen, this.camera);
}

class RoadSegment {
  int index;
  bool light;
  RoadSegmentPoint p1;
  RoadSegmentPoint p2;

  RoadSegment(this.index, this.light, this.p1, this.p2);
}

class MyGame extends BaseGame {

  static final Paint darkRoadSegmentPaint = Paint()..color = Color(0xFF603e4e);
  static final Paint lightRoadSegmentPaint = Paint()..color = Color(0xFF9f6a7a);
  static final Paint backgroundPaint = Paint()..color = Color(0xFF120d11);

  static final math.Random random = math.Random();

  FlameAnimation.Animation playerAnimation;
  Sprite background;
  Size size;

  bool loaded = false;

  static double segmentLength = 200;
  static int fieldOfView = 100;
  static double cameraHeight = 1000;
  static double cameraDepth = 1 / math.tan((fieldOfView / 2) * math.pi / 180);
  static double maxSpeed = segmentLength / 16;

  List<RoadSegment> segments;
  double roadWidth = 2000;
  int rumbleLength = 3;
  double trackLength;
  int lanes = 3;
  int drawDistance = 300;

  static double playerWidth = 256;
  static double playerHeight = 128;
  double playerX = 0;
  double playerZ = (cameraHeight * cameraDepth);

  int fogDensity = 5;
  double position = 10;
  int speed = 4000;
  double accel = maxSpeed / 5;
  double breaking = -maxSpeed;
  double decel = -maxSpeed / 5;
  double offRoadDecel = -maxSpeed / 2;
  double offRoadLimit =  maxSpeed / 4;

  void resetRoad() {
    segments = new List(500);

    for (int n = 0; n < 500; n++) {
      segments[n] = RoadSegment(
        n,
        (n / rumbleLength).floor() % 2 == 0,
        RoadSegmentPoint(0, 0, n * segmentLength, Screen(), Camera()),
        RoadSegmentPoint(0, 0, (n + 1) * segmentLength, Screen(), Camera())
      );
    }

    trackLength = segments.length * segmentLength;
  }

  RoadSegment findSegment(int z) {
    return segments[((z / segmentLength) % segments.length).floor()];
  }

  void projectRoadSegmentPoint(RoadSegmentPoint p, double cameraX, double cameraY, double cameraZ, double cameraDepth, double width, double height, double roadWidth) {
    p.camera.x     = p.worldX - cameraX;
    p.camera.y     = p.worldY - cameraY;
    p.camera.z     = p.worldZ - cameraZ;
    p.screen.scale = cameraDepth/p.camera.z;
    p.screen.x     = ((width/2)  + (p.screen.scale * p.camera.x  * width/2)).round().toDouble();
    p.screen.y     = ((height/2) - (p.screen.scale * p.camera.y  * height/2)).round().toDouble();
    p.screen.width     = ((p.screen.scale * roadWidth   * width/2)).round().toDouble();
  }

  void renderRoad(Canvas canvas) {
    final baseSegment = findSegment(0); // TODO where does this position comes from?
    final maxY = size.height;

    int n;
    RoadSegment segment;

    for (n = 0; n < drawDistance; n++) {
      segment = segments[(baseSegment.index + n) % segments.length];

      projectRoadSegmentPoint(segment.p1, (playerX * roadWidth), cameraHeight, position, cameraDepth, size.width, size.height, roadWidth);
      projectRoadSegmentPoint(segment.p2, (playerX * roadWidth), cameraHeight, position, cameraDepth, size.width, size.height, roadWidth);

      if ((segment.p1.camera.z <= cameraDepth) || // behind us
          (segment.p2.screen.y >= maxY))          // clip by (already rendered) segment
        continue;

      renderSegment(canvas, size.width, lanes,
        segment.p1.screen.x,
        segment.p1.screen.y,
        segment.p1.screen.width,
        segment.p2.screen.x,
        segment.p2.screen.y,
        segment.p2.screen.width,
        segment.light ? lightRoadSegmentPaint : darkRoadSegmentPaint
      );
    }
  }

  void polygon(Canvas c, double x1, double y1, double x2, y2, double x3, double y3, double x4, double y4, Paint color) {
    Path path = Path();
    path.moveTo(x1, y1);
    path.lineTo(x2, y2);
    path.lineTo(x3, y3);
    path.lineTo(x4, y4);
    path.close();

    c.drawPath(path, color);
  }

  void renderSegment(Canvas c, double width, int lanes, double x1, double y1, double w1, double x2, double y2, double w2, Paint paint) {
    polygon(c, x1-w1, y1, x1+w1, y1, x2+w2, y2, x2-w2, y2, paint);
  }

  MyGame() {
    _start();
  }

  void _start() async {
    await Flame.util.fullScreen();
    await Flame.util.setOrientation(DeviceOrientation.landscapeRight);
    size = await Flame.util.initialDimensions();
    background = await Sprite.loadSprite("backgrounds/city.png");
    playerAnimation = FlameAnimation.Animation.sequenced("cars/time-splitter.png", 2, textureWidth: 64, textureHeight: 48);

    //playerX = (size.width / 2) - playerWidth / 2;
    resetRoad();

    loaded = true;
  }

  render(Canvas canvas) {
    if (!loaded) return;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
    background.renderRect(canvas, Rect.fromLTWH(0, 0, size.width, size.height / 2));
    renderRoad(canvas);

    if (playerAnimation.loaded()) {
      final bounce = random.nextBool() ? 1 : -1;
      playerAnimation.getSprite().renderRect(
        canvas,
        Rect.fromLTWH(
          playerX + (size.width / 2) - playerWidth / 2,
          size.height - playerHeight + bounce,
          playerWidth,
          playerHeight
        )
      );
    }
  }


  double increase(double start, double increment, double max) {
    var result = start + increment;
    while (result >= max)
      result -= max;
    while (result < 0)
      result += max;
    return result;
  }

  update(double dt) {
    if (!loaded) return;
    position = increase(position, dt * speed, trackLength);

    playerAnimation.update(dt);
  }
}

