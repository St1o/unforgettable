import 'dart:collection';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models/node.dart';

// "Модель" машинного обучения для предсказания оптимального коэффициента
class RouteMLModel {
  double predictCoefficient({required double routeLength, required int numNodes}) {
    return (routeLength / (numNodes + 1)) * 0.05 + 1.0;
  }
}

typedef Heuristic = double Function(LatLng a, LatLng b);
typedef DistanceFunction = double Function(LatLng a, LatLng b);

double _defaultHeuristic(LatLng a, LatLng b) {
  return (a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs();
}

double _defaultDistance(LatLng a, LatLng b) {
  return (a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs();
}

class AStarSearch {
  final List<LatLng> points;
  final Map<Node, List<Node>> graph;
  final Node start;
  final Node goal;
  double coefficient; // Коэффициент, влияющий на эвристику
  final Heuristic heuristic;
  final DistanceFunction distanceFunction;
  final RouteMLModel? mlModel;

  AStarSearch({
    required this.points,
    required this.graph,
    required this.start,
    required this.goal,
    required this.coefficient,
    Heuristic? heuristic,
    DistanceFunction? distanceFunction,
    this.mlModel,
  })  : heuristic = heuristic ?? _defaultHeuristic,
        distanceFunction = distanceFunction ?? _defaultDistance {
    // Если ML-модель предоставлена, обновляем коэффициент по её предсказанию
    if (mlModel != null) {
      coefficient = mlModel!.predictCoefficient(
        routeLength: distanceFunction!(points[start.id], points[goal.id]),
        numNodes: graph.length,
      );
    }
  }

  List<LatLng>? search({bool verbose = false}) {
    final queue = PriorityQueue<MapEntry<Node, double>>(
        (a, b) => a.value.compareTo(b.value));
    final Map<Node, double> costSoFar = {};
    final Map<Node, Node> cameFrom = {};

    queue.add(MapEntry(start, 0));
    costSoFar[start] = 0;
    cameFrom[start] = start;

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (verbose) print("Processing: ${current.key}");
      if (current.key == goal) break;
      for (final next in graph[current.key] ?? <Node>[]) {
        double newCost = costSoFar[current.key]! +
            distanceFunction(points[current.key.id], points[next.id]);
        if (!costSoFar.containsKey(next) || newCost < costSoFar[next]!) {
          costSoFar[next] = newCost;
          double priority = newCost +
              heuristic(points[next.id], points[goal.id]) * coefficient;
          queue.add(MapEntry(next, priority));
          cameFrom[next] = current.key;
          if (verbose) {
            print("Update: ${next} cost: $newCost priority: $priority");
          }
        }
      }
    }
    if (!cameFrom.containsKey(goal)) return null;
    return _reconstructPath(cameFrom, start, goal);
  }

  List<LatLng> _reconstructPath(Map<Node, Node> cameFrom, Node start, Node goal) {
    final path = <LatLng>[];
    Node current = goal;
    while (current != start) {
      path.insert(0, points[current.id]);
      current = cameFrom[current]!;
    }
    path.insert(0, points[start.id]);
    return path;
  }

  List<LatLng>? searchWithDebug() {
    return search(verbose: true);
  }
}
