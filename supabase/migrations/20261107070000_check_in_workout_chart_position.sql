-- A 训练 from Apple Health with a route can show its map and its heart-rate chart together
-- (Tracy, 2026-11-07), so a workout keeps up to two tiles among its photos. `tile_position`
-- stays the map's place when there is a route, else the chart's, so builds from before read
-- the map as they did; `chart_position` is the chart's place when the map is kept too.
alter table public.check_in_workouts
  drop constraint check_in_workouts_tile_position_check,
  drop constraint check_in_workouts_check1,
  -- 3 photos and both tiles.
  add constraint check_in_workouts_tile_position_check check (tile_position between 1 and 5),
  add column chart_position smallint
    constraint check_in_workouts_chart_position_check check (chart_position between 1 and 5),
  add constraint check_in_workouts_tiles_match_data check (
    (tile_position is null) = (series is null and route is null)
    and (chart_position is null) = (series is null or route is null)
    and (chart_position is null or chart_position <> tile_position)
  );
