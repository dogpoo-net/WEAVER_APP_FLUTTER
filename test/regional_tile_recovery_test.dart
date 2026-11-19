import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:weaver/features/capture/regional_tiles.dart';

class DelayedTiles extends http.BaseClient {
  final entered = Completer<void>(), release = Completer<void>();
  final Uint8List bytes;
  DelayedTiles(this.bytes);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!entered.isCompleted) entered.complete();
    await Future.any<void>([
      release.future,
      if (request is http.Abortable && request.abortTrigger != null)
        request.abortTrigger!.then(
          (_) => throw http.RequestAbortedException(request.url),
        ),
    ]);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      headers: {'content-type': 'image/png'},
    );
  }
}

Future<ui.Image> resolve(ImageProvider provider) {
  final result = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      result.complete(info.image.clone());
    },
    onError: (Object e, StackTrace? s) {
      stream.removeListener(listener);
      result.completeError(e, s);
    },
  );
  stream.addListener(listener);
  return result.future;
}

class BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) =>
      MemoryImage(TileProvider.transparentImage);
}

class RetryTile extends TileImage {
  RetryTile()
    : super(
        errorImage: null,
        cancelLoading: Completer<void>(),
        coordinates: const TileCoordinates(0, 0, 2),
        vsync: TestVSync(),
        imageProvider: MemoryImage(TileProvider.transparentImage),
        tileDisplay: const TileDisplay.instantaneous(),
        onLoadComplete: (_) {},
        onLoadError: (_, _, _) {},
      );
  int loads = 0;
  @override
  void load() {
    loads++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fixed in [false, true]) {
    test(
      'shared in-flight tile survives obsolete consumer cancellation: fixed=$fixed',
      () async {
        PaintingBinding.instance.imageCache.clear();
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
        final client = DelayedTiles(bytes);
        final cancelled = Completer<void>();
        final provider = fixed
            ? RegionalTileProvider(
                httpClient: client,
                cachingProvider: const DisabledMapCachingProvider(),
              )
            : NetworkTileProvider(
                httpClient: client,
                cachingProvider: const DisabledMapCachingProvider(),
              );
        final options = TileLayer(urlTemplate: globalTileTemplate);
        final one = provider.getImageWithCancelLoadingSupport(
          const TileCoordinates(2, 1, 2),
          options,
          cancelled.future,
        );
        final two = provider.getImageWithCancelLoadingSupport(
          const TileCoordinates(2, 1, 2),
          options,
          Completer<void>().future,
        );
        final first = resolve(one), second = resolve(two);
        await client.entered.future;
        cancelled.complete();
        await Future<void>.delayed(Duration.zero);
        client.release.complete();
        final results = await Future.wait([first, second]);
        for (final result in results) {
          expect(result.width, fixed ? 2 : 1);
          result.dispose();
        }
        await provider.dispose();
        client.close();
        PaintingBinding.instance.imageCache.clear();
      },
    );
  }
  test('HTTP error image is not accepted as a successful tile', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(TileProvider.transparentImage, 403),
    );
    final provider = RegionalTileProvider(
      httpClient: client,
      cachingProvider: const DisabledMapCachingProvider(),
    );
    final image = provider.getImageWithCancelLoadingSupport(
      const TileCoordinates(1, 1, 2),
      TileLayer(urlTemplate: globalTileTemplate),
      Completer<void>().future,
    );
    await expectLater(
      resolve(image),
      throwsA(isA<NetworkImageLoadException>()),
    );
    await provider.dispose();
    client.close();
  });
  testWidgets('hidden maps pause retries and disposed tiles are ignored', (
    tester,
  ) async {
    var active = true;
    late StateSetter update;
    final tile = RetryTile()..loadError = true;
    final map = FlutterMap(
      options: const MapOptions(initialCenter: LatLng(20, 0), initialZoom: 2),
      children: [RegionalTileLayer(tileProvider: BlankTiles())],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            update = set;
            return TickerMode(enabled: active, child: map);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    layer.errorTileCallback!(tile, StateError('offline'), null);
    update(() => active = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 40));
    expect(tile.loads, 0);
    update(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(tile.loads, 1);
    layer.errorTileCallback!(tile, StateError('offline'), null);
    tile.dispose();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(tile.loads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed tiles keep retrying beyond two attempts without resetting healthy tiles',
    (tester) async {
      final tile = RetryTile()..loadError = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(20, 0),
                initialZoom: 2,
              ),
              children: [RegionalTileLayer(tileProvider: BlankTiles())],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.reset, isNull);
      for (final delay in [2, 4, 8, 16]) {
        layer.errorTileCallback!(tile, StateError('temporary failure'), null);
        await tester.pump(Duration(seconds: delay));
        await tester.pump();
      }
      expect(tile.loads, 4);
      tile.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 40));
      expect(tester.takeException(), isNull);
    },
  );
}
