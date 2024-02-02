import pkg/godot
import godotapi/[ray_cast]
import core, models/[units]

proc run*(query: var SightQuery, source: Unit) =
  assert not ?query.answer
  query.answer = some(false)

  let ray = source.sight_ray
  let target_position = source.node.to_local(query.target.position)
  let angle = target_position - ray.transform.origin

  if angle.length <= query.distance and angle.normalized.z <= -0.3:
    ray.cast_to = angle

    ray.force_raycast_update
    if ray.is_colliding:
      let collider = ray.get_collider as Spatial
      if collider == query.target.node:
        query.answer = some(true)
