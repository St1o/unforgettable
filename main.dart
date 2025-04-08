import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'locator.dart';
import 'country_codes.dart';
import 'hive_adapters.dart';
import 'app_styles.dart';

// Подключение API-ключей для Google Maps. Используйте ваш API-ключ
const String googleMapsApiKey = 'Ri4R2lnFbHS2u4wFoD6ilrejOFpQ1hdP6MGBK1x';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Настройки системного интерфейса
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppStyles.darkStyle);

  // Ограничение ориентаций экрана (только портрет)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Инициализация сервисов и локаторов
  await setUpLocator();
  await CountryCodes.init();

  // Получение директории для хранения данных и настройка Hive
  Directory directory = await getApplicationDocumentsDirectory();
  Hive
    ..init(directory.path)
    ..registerAdapter(SaveRouteEntityAdapter())
    ..registerAdapter(DirectionAdapter())
    ..registerAdapter(TransportTypeAdapter());

  // Запуск приложения в защищенной зоне для перехвата ошибок
  runZonedGuarded(() {
    runApp(const App());
  }, (error, stackTrace) {
    print('runZonedGuarded: Caught error in my root zone.\n$error $stackTrace');
  });
}

// Минимальный виджет приложения.
class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Приложение с Картой',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}

// Простой домашний экран (его можно расширять по необходимости)
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
      ),
      body: const Center(
        child: Text('Добро пожаловать в приложение с картой!'),
      ),
    );
  }
}


Future<void> main() async {
  // Инициализация Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Настройки системного интерфейса
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppStyles.darkStyle);

  // Ограничение ориентаций экрана
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Инициализация сервисов и локаторов
  await setUpLocator();
  await CountryCodes.init();

  // Получение директории для хранения данных и настройка Hive
  Directory directory = await pathProvider.getApplicationDocumentsDirectory();
  Hive
    ..init(directory.path)
    ..registerAdapter(SaveRouteEntityAdapter())
    ..registerAdapter(DirectionAdapter())
    ..registerAdapter(TransportTypeAdapter());

  // Запуск приложения в защищенной зоне для перехвата ошибок
  runZonedGuarded(() {
    runApp(App());
  }, (error, stackTrace) {
    print('runZonedGuarded: Caught error in my root zone.\n$error $stackTrace');
  });
}

FutureOr<void> _getSights(GetSights event, Emitter<MapState> emit) async {
  // Получаем границы видимой области карты
  LatLngBounds latLngBounds = await _mapController.getVisibleRegion();

  // Формируем тело запроса для получения объектов достопримечательностей
  GetFeaturesBody getFeaturesBody = GetFeaturesBody(
    lonMin: latLngBounds.southwest.longitude,
    lonMax: latLngBounds.northeast.longitude,
    latMin: latLngBounds.southwest.latitude,
    latMax: latLngBounds.northeast.latitude,
  );

  // Выполняем запрос к репозиторию карт
  Either<List<SightEntity>, Failure> result = await mapRepository.getSights(
    body: getFeaturesBody,
  );

  // Обрабатываем результат запроса
  result.fold(
    (data) {
      // Очищаем список перед применением фильтров
      emit(state.copyWith(sights: []));
      // Применяем фильтры к полученным данным и обновляем состояние
      emit(state.copyWith(sights: _filtersApply(data)));
    },
    (error) {
    },
  );
}

void _aStarSearch(
  List<LatLng> points,
  Map<Node, List<Node>> graph,
  Node start,
  Node goal,
) {
  // Карта предыдущих узлов для восстановления маршрута
  Map<Node, Node> cameFrom = {};
  // Карта накопленной стоимости пути до узла
  Map<Node, double> costSoFar = {};

  // Коэффициент для оценки расстояния от текущей точки до цели
  double coefficientCurrentLengthToFinish = state.routeInterestValue;

  // Очередь с приоритетом для реализации алгоритма A*
  PriorityQueue<MapEntry<Node, double>> priorityQueue =
      PriorityQueue<MapEntry<Node, double>>(
    (min, max) => min.value.compareTo(max.value),
  );

  // Инициализация очереди и начальных значений для старта
  priorityQueue.add(MapEntry<Node, double>(start, 0));
  cameFrom[start] = start;
  costSoFar[start] = 0;

  double minDistance = 999.0;

  // Основной цикл поиска пути
  while (priorityQueue.isNotEmpty) {
    var current = priorityQueue.removeFirst();

    // Если достигнута цель, прерываем цикл
    if (current.key == goal) {
      break;
    }

    // Обрабатываем всех соседей текущего узла
    graph[current.key]?.forEach((next) {
      double distanceNextToFinish =
          _getManhattanDistance(points[next.id], points[goal.id]);
      double distanceCurrentToFinish =
          _getManhattanDistance(points[current.key.id], points[goal.id]);
      double distance = _getManhattanDistance(
            points[current.key.id],
            points[next.id],
          ) +
          distanceNextToFinish * coefficientCurrentLengthToFinish;

      // Проверяем, является ли найденный путь улучшением текущего минимального расстояния
      if (distance < minDistance &&
          distanceNextToFinish < distanceCurrentToFinish) {
        minDistance = distance;
        priorityQueue.add(MapEntry<Node, double>(next, distance));
        cameFrom[next] = current.key;
      }
    });
  }

  // Восстанавливаем маршрут по ключам из карты cameFrom
  List<LatLng> pointsRoute =
      cameFrom.keys.map((key) => points[key.id]).toList();
  // Добавляем конечную точку
  pointsRoute.add(points.last);

  // Отправляем событие построения маршрута с достопримечательностями
  this.add(MapEvent.buildRouteWithSights(pointsRoute));
}

FutureOr<void> _buildRouteWithSights(
  BuildRouteWithSights event,
  Emitter<MapState> emit,
) async {
  // Инициализация переменной для хранения направления маршрута.
  Direction? direction;
  // Формирование строки координат на основе точек маршрута.
  String coordinates = _getStringCoordinates(event.points);

  // Запрос к directionsRepository для построения маршрута.
  Either<Direction, Failure> result = await directionsRepository.buildRoute(
    profile: state.selectedTransport.name,
    coordinates: coordinates,
  );

  // Обработка результата запроса.
  result.fold(
    (data) {
      direction = data;
    },
    (error) {
    },
  );

  // Если направление маршрута получено, обновляем состояние и перемещаем камеру карты.
  if (direction != null) {
    emit(state.copyWith(
      currentDirection: direction,
      countSightsInRoute: event.points.length - 2,
    ));
    _mapController.animateCamera(
      CameraUpdate.newLatLng(event.points.first),
    );
  }
}
