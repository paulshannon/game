class_name Replication
extends RefCounted
## Builds MultiplayerSynchronizers in code.
##
## Doing this in code instead of the editor's Replication panel keeps the
## synced property list visible in the script that owns those properties,
## and avoids hand-editing SceneReplicationConfig sub-resources in .tscn files.


## Synchronizer that replicates `always_props` every snapshot and
## `on_change_props` only when they change. All are also sent at spawn time,
## so a late joiner gets the current values immediately.
## Property names are on the synchronizer's parent node.
static func make_synchronizer(always_props: PackedStringArray,
		on_change_props: PackedStringArray = PackedStringArray()) -> MultiplayerSynchronizer:
	var cfg := SceneReplicationConfig.new()
	for prop: String in always_props:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for prop: String in on_change_props:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / Protocol.SNAPSHOT_HZ
	sync.delta_interval = 1.0 / Protocol.SNAPSHOT_HZ
	# Authority stays with the server (peer 1, the default). Clients never
	# write gameplay state; they only send input through InputRelay.
	return sync
