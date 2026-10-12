import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/pose_coordinates.dart';

void main() {
  test('upright matching aspect ratio and mirroring', () {
    expect(mapPosePoint(const Offset(.25, .75), const Size(300, 400), const Size(600, 800)), const Offset(150, 600));
    expect(mapPosePoint(const Offset(.25, .75), const Size(300, 400), const Size(600, 800), mirror: true), const Offset(450, 600));
  });
  test('quarter rotations are applied before mirroring', () {
    expect(mapPosePoint(const Offset(.25, .75), const Size(400, 300), const Size(300, 400), rotation: 90), const Offset(75, 100));
    expect(mapPosePoint(const Offset(.25, .75), const Size(400, 300), const Size(300, 400), rotation: 270, mirror: true), const Offset(75, 300));
    expect(mapPosePoint(const Offset(.25, .75), const Size(300, 400), const Size(300, 400), rotation: 180), const Offset(225, 100));
  });
  test('cover crop preserves centre and scale', () {
    expect(mapPosePoint(const Offset(.5, .5), const Size(400, 300), const Size(300, 300)), const Offset(150, 150));
    expect(mapPosePoint(Offset.zero, const Size(400, 300), const Size(300, 300)), const Offset(-50, 0));
  });
}
