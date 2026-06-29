class GameMap {
  const GameMap({
    required this.id,
    required this.name,
    required this.style,
    required this.assetPath,
  });

  final String id;
  final String name;
  final String style;
  final String assetPath;
}

class GameMaps {
  static const defaultId = 'sunken_reef';

  static const all = [
    GameMap(
      id: defaultId,
      name: '沉船礁湖',
      style: '明亮海底',
      assetPath: 'assets/images/ocean_world_wide.png',
    ),
    GameMap(
      id: 'coral_garden',
      name: '珊瑚花園',
      style: '明亮珊瑚',
      assetPath: 'assets/images/map_coral_garden.png',
    ),
    GameMap(
      id: 'shipwreck_ruins',
      name: '沉船遺跡',
      style: '沉船遺跡',
      assetPath: 'assets/images/map_shipwreck_ruins.png',
    ),
    GameMap(
      id: 'pirate_wreck',
      name: '海盜殘骸',
      style: '沉船遺跡',
      assetPath: 'assets/images/map_pirate_wreck.png',
    ),
    GameMap(
      id: 'kelp_forest',
      name: '海草森林',
      style: '海草藍洞',
      assetPath: 'assets/images/map_kelp_forest.png',
    ),
    GameMap(
      id: 'blue_cave',
      name: '藍洞礁岩',
      style: '海草藍洞',
      assetPath: 'assets/images/map_blue_cave.png',
    ),
  ];

  static GameMap byId(String id) {
    for (final map in all) {
      if (map.id == id) return map;
    }
    return all.first;
  }
}
