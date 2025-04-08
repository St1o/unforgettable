import 'dart:async';
import 'dart:collection';

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'models/sight_entity.dart';
import 'models/failure.dart';
import 'models/direction.dart';
import 'models/transport.dart';
import 'models/node.dart';
import 'models/get_features_body.dart';
import 'repositories/map_repository.dart';
import 'repositories/directions_repository.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class InitializeMap extends MapEvent {}

class UpdateMapController extends MapEvent {
  final GoogleMapController controller;
  const UpdateMapController(this.controller);
  @override
  List<Object?> get props => [controller];
}

class GetSights extends MapEvent {}

class BuildRouteWithSights extends MapEvent {
  final List<LatLng> points;
  const BuildRouteWithSights(this.points);
  @override
  List<Object?> get props => [points];
}

class ClearRoute extends MapEvent {}

class SelectTransport extends MapEvent {
  final Transport selectedTransport;
  const SelectTransport(this.selectedTransport);
  @override
  List<Object?> get props => [selectedTransport];
}

class UpdateFilters extends MapEvent {
  final Map<String, dynamic> filters;
  const UpdateFilters(this.filters);
  @override
  List<Object?> get props => [filters];
}

class ComputeRouteDistance extends MapEvent {
  final List<LatLng> points;
  const ComputeRouteDistance(this.points);
  @override
  List<Object?> get props => [points];
}

enum MapStatus { initial, loading, loaded, error }

class MapState extends Equatable {
  final List<SightEntity> sights;
  final Direction? currentDirection;
  final int countSightsInRoute;
  final double routeInterestValue;
  final Transport selectedTransport;
  final String? errorMessage;
  final MapStatus status;
  final double routeDistance;
  final Map<String, dynamic> activeFilters;

  const MapState({
    this.sights = const [],
    this.currentDirection,
    this.countSightsInRoute = 0,
    required this.routeInterestValue,
    required this.selectedTransport,
    this.errorMessage,
    this.status = MapStatus.initial,
    this.routeDistance = 0.0,
    this.activeFilters = const {},
  });

  MapState copyWith({
    List<SightEntity>? sights,
    Direction? currentDirection,
    int? countSightsInRoute,
    double? routeInterestValue,
    Transport? selectedTransport,
    String? errorMessage,
    MapStatus? status,
    double? routeDistance,
    Map<String, dynamic>? activeFilters,
  }) {
    return MapState(
      sights: sights ?? this.sights,
      currentDirection: currentDirection ?? this.currentDirection,
      countSightsInRoute: countSightsInRoute ?? this.countSightsInRoute,
      routeInterestValue: routeInterestValue ?? this.routeInterestValue,
      selectedTransport: selectedTransport ?? this.selectedTransport,
      errorMessage: errorMessage,
      status: status ?? this.status,
      routeDistance: routeDistance ?? this.routeDistance,
      activeFilters: activeFilters ?? this.activeFilters,
    );
  }

  @override
  List<Object?> get props => [
        sights,
        currentDirection,
        countSightsInRoute,
        routeInterestValue,
        selectedTransport,
        errorMessage,
        status,
        routeDistance,
        activeFilters,
      ];
}

class MapBloc extends Bloc<MapEvent, MapState> {
  final MapRepository mapRepository;
  final DirectionsRepository directionsRepository;
  GoogleMapController? _mapController;

  MapBloc({
    required this.mapRepository,
    required this.directionsRepository,
    required Transport selectedTransport,
    required double routeInterestValue,
  }) : super(MapState(
          selectedTransport: selectedTransport,
          routeInterestValue: routeInterestValue,
        )) {
    on<InitializeMap>(_onInitializeMap);
    on<UpdateMapController>(_onUpdateMapController);
    on<GetSights>(_onGetSights);
    on<BuildRouteWithSights>(_onBuildRouteWithSights);
    on<ClearRoute>(_onClearRoute);
    on<SelectTransport>(_onSelectTransport);
    on<UpdateFilters>(_onUpdateFilters);
    on<ComputeRouteDistance>(_onComputeRouteDistance);
  }

  FutureOr<void> _onInitializeMap(InitializeMap event, Emitter<MapState> emit) async {
    debugPrint('Map init started.');
    emit(state.copyWith(status: MapStatus.loading));
    await Future.delayed(Duration(milliseconds: 100));
    emit(state.copyWith(status: MapStatus.loaded));
    debugPrint('Map init completed.');
  }

  FutureOr<void> _onUpdateMapController(UpdateMapController event, Emitter<MapState> emit) {
    _mapController = event.controller;
    debugPrint('Controller updated.');
  }

  FutureOr<void> _onGetSights(GetSights event, Emitter<MapState> emit) async {
    if (_mapController == null) {
      emit(state.copyWith(status: MapStatus.error, errorMessage: 'No controller'));
      return;
    }
    emit(state.copyWith(status: MapStatus.loading));
    try {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      GetFeaturesBody body = GetFeaturesBody(
        lonMin: bounds.southwest.longitude,
        lonMax: bounds.northeast.longitude,
        latMin: bounds.southwest.latitude,
        latMax: bounds.northeast.latitude,
      );
      Either<List<SightEntity>, Failure> result = await mapRepository.getSights(body: body);
      result.fold(
        (data) {
          List<SightEntity> filtered = _applyFilters(data, state.activeFilters);
          emit(state.copyWith(sights: filtered, status: MapStatus.loaded));
          debugPrint('Fetched ${filtered.length} sights.');
        },
        (failure) {
          emit(state.copyWith(status: MapStatus.error, errorMessage: failure.message));
          debugPrint('Error fetching sights: ${failure.message}');
        },
      );
    } catch (e) {
      emit(state.copyWith(status: MapStatus.error, errorMessage: e.toString()));
      debugPrint('Exception in GetSights: $e');
    }
  }

  FutureOr<void> _onBuildRouteWithSights(BuildRouteWithSights event, Emitter<MapState> emit) async {
    emit(state.copyWith(status: MapStatus.loading));
    Direction? direction;
    try {
      String coords = _getStringCoordinates(event.points);
      Either<Direction, Failure> result = await directionsRepository.buildRoute(
        profile: state.selectedTransport.name,
        coordinates: coords,
      );
      result.fold(
        (data) { direction = data; debugPrint('Route direction obtained.'); },
        (failure) {
          emit(state.copyWith(status: MapStatus.error, errorMessage: failure.message));
          debugPrint('Error building route: ${failure.message}');
        },
      );
      if (direction != null) {
        emit(state.copyWith(
          currentDirection: direction,
          countSightsInRoute: event.points.length - 2,
          status: MapStatus.loaded,
        ));
        _mapController?.animateCamera(CameraUpdate.newLatLng(event.points.first));
      }
    } catch (e) {
      emit(state.copyWith(status: MapStatus.error, errorMessage: e.toString()));
      debugPrint('Exception in BuildRoute: $e');
    }
  }

  FutureOr<void> _onClearRoute(ClearRoute event, Emitter<MapState> emit) {
    emit(state.copyWith(currentDirection: null, countSightsInRoute: 0));
    debugPrint('Route cleared.');
  }

  FutureOr<void> _onSelectTransport(SelectTransport event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedTransport: event.selectedTransport));
    debugPrint('Transport selected: ${event.selectedTransport.name}');
  }

  FutureOr<void> _onUpdateFilters(UpdateFilters event, Emitter<MapState> emit) {
    emit(state.copyWith(activeFilters: event.filters));
    debugPrint('Filters updated.');
    add(GetSights());
  }

  FutureOr<void> _onComputeRouteDistance(ComputeRouteDistance event, Emitter<MapState> emit) {
    double totalDistance = 0.0;
    for (int i = 1; i < event.points.length; i++) {
      totalDistance += _getManhattanDistance(event.points[i - 1], event.points[i]);
    }
    emit(state.copyWith(routeDistance: totalDistance));
    debugPrint('Computed route distance: $totalDistance');
  }

  List<SightEntity> _applyFilters(List<SightEntity> sights, Map<String, dynamic> filters) {
    if (filters.isEmpty) return sights;
    return sights.where((sight) {
      if (filters.containsKey('minRating')) {
        double minRating = filters['minRating'];
        return sight.rating >= minRating;
      }
      return true;
    }).toList();
  }

  String _getStringCoordinates(List<LatLng> points) {
    String coords = points.map((p) => "${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}").join(";");
    debugPrint('Coordinates: $coords');
    return coords;
  }

  void aStarSearch(List<LatLng> points, Map<Node, List<Node>> graph, Node start, Node goal) {
    Map<Node, Node> cameFrom = {};
    Map<Node, double> costSoFar = {};
    double coeff = state.routeInterestValue;
    PriorityQueue<MapEntry<Node, double>> queue = PriorityQueue<MapEntry<Node, double>>((a, b) => a.value.compareTo(b.value));
    queue.add(MapEntry<Node, double>(start, 0));
    cameFrom[start] = start;
    costSoFar[start] = 0;
    while (queue.isNotEmpty) {
      var current = queue.removeFirst();
      if (current.key == goal) break;
      graph[current.key]?.forEach((next) {
        double costCurrentToNext = _getManhattanDistance(points[current.key.id], points[next.id]);
        double tentativeCost = (costSoFar[current.key] ?? double.infinity) + costCurrentToNext;
        double priority = tentativeCost + _getManhattanDistance(points[next.id], points[goal.id]) * coeff;
        if (tentativeCost < (costSoFar[next] ?? double.infinity)) {
          costSoFar[next] = tentativeCost;
          queue.add(MapEntry<Node, double>(next, priority));
          cameFrom[next] = current.key;
          debugPrint('Updated node ${next} with priority $priority');
        }
      });
    }
    List<LatLng> route = _reconstructPath(cameFrom, start, goal, points);
    add(BuildRouteWithSights(route));
    debugPrint('A* search completed. Route has ${route.length} points.');
  }

  List<LatLng> _reconstructPath(Map<Node, Node> cameFrom, Node start, Node goal, List<LatLng> points) {
    List<LatLng> path = [];
    Node? current = goal;
    while (current != null && current != start) {
      path.insert(0, points[current.id]);
      current = cameFrom[current];
    }
    path.insert(0, points[start.id]);
    if (path.last != points[goal.id]) path.add(points[goal.id]);
    return path;
  }

  double _getManhattanDistance(LatLng p1, LatLng p2) {
    return (p1.latitude - p2.latitude).abs() + (p1.longitude - p2.longitude).abs();
  }
}
