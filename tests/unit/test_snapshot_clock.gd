extends TestCase
## Plays a simulated 20 Hz snapshot stream of a player moving at constant
## speed through SnapshotClock + SnapshotBuffer, rendering at 60 fps, and
## measures how far the drawn position jumps in any one frame.

const SPEED: float = 300.0        # units per second
const SEND_DT: float = 1.0 / 20.0
const FRAME_DT: float = 1.0 / 60.0
const LATENCY: float = 0.03


## Largest per-frame movement while a stall of `hitch` seconds (starting at
## t=2 s) holds back every snapshot, which then all arrive in one burst.
## `arrival_stamps` reproduces the old behaviour (buffer by arrival time).
func _max_frame_step(hitch: float, arrival_stamps: bool = false) -> float:
	var clock := SnapshotClock.new()
	var buf := SnapshotBuffer.new()
	# Arrival time of each snapshot: normal latency, except those sent during
	# the stall, which all arrive together when it ends.
	var sends: Array[float] = []
	var arrivals: Array[float] = []
	var t: float = 0.0
	while t < 5.0:
		sends.append(t)
		var arrive: float = t + LATENCY
		if t >= 2.0 and t < 2.0 + hitch:
			arrive = 2.0 + hitch + LATENCY
		arrivals.append(arrive)
		t += SEND_DT
	var next: int = 0
	var last_pos: float = NAN
	var worst: float = 0.0
	var now: float = 0.0
	while now < 5.0:
		while next < sends.size() and arrivals[next] <= now:
			clock.observe(sends[next], arrivals[next])
			buf.push(arrivals[next] if arrival_stamps else sends[next], Vector2(sends[next] * SPEED, 0))
			next += 1
		if clock.is_synced():
			var at: float = now - Protocol.INTERP_DELAY if arrival_stamps else clock.render_time(now)
			var p: float = (buf.sample(at) as Vector2).x
			if not is_nan(last_pos) and now > 1.0:  # skip warm-up
				worst = maxf(worst, absf(p - last_pos))
			last_pos = p
		now += FRAME_DT
	return worst


func test_steady_stream_moves_one_frame_at_a_time() -> void:
	assert_near(_max_frame_step(0.0), SPEED * FRAME_DT, 0.5)


## Extra delay a snapshot can take without any visible hitch: playback needs
## the NEXT snapshot by the time it reaches the current one.
func _slack() -> float:
	return Protocol.INTERP_DELAY - SEND_DT - LATENCY


func test_stall_within_slack_stays_smooth() -> void:
	assert_near(_max_frame_step(_slack() - 0.01), SPEED * FRAME_DT, 0.5)


func test_long_stall_catches_up_by_only_the_excess() -> void:
	# A 150 ms stall outlasts the slack: the player pauses, then catches up by
	# about the excess in one frame instead of skipping the whole burst.
	var step: float = _max_frame_step(0.15)
	var bound: float = SPEED * (0.15 - _slack() + 2.0 * FRAME_DT)
	assert_true(step <= bound, "max frame step %.1f > %.1f" % [step, bound])


func test_server_stamps_beat_arrival_stamps() -> void:
	# The bug this class fixes (#2): burst snapshots stamped ~0 s apart.
	var fixed: float = _max_frame_step(0.15)
	var old: float = _max_frame_step(0.15, true)
	assert_true(fixed < old * 0.7, "fixed %.1f vs arrival-stamped %.1f" % [fixed, old])


func test_offset_ignores_late_packets() -> void:
	var clock := SnapshotClock.new()
	clock.observe(1.0, 1.05)
	clock.observe(1.05, 1.40)  # stalled packet: much larger offset
	assert_near(clock.render_time(2.0), 2.0 - 0.05 - Protocol.INTERP_DELAY)


func test_offset_follows_latency_change_gradually() -> void:
	var clock := SnapshotClock.new()
	clock.observe(0.0, 0.2)          # first packet was slow: offset 0.2
	clock.observe(1.0, 1.05)         # latency is really 0.05
	# One second later the offset may only have moved by MAX_SLEW.
	assert_near(clock.render_time(1.05), 1.05 - (0.2 - SnapshotClock.MAX_SLEW * 0.85) - Protocol.INTERP_DELAY, 0.0001)


func test_far_behind_after_a_slow_start_jumps_forward() -> void:
	# The first snapshots were held up 2 s (the client was loading); slewing
	# back at MAX_SLEW would draw everything 2 s late for 20 s.
	var clock := SnapshotClock.new()
	clock.observe(0.0, 2.05)
	clock.observe(2.0, 2.05)         # latency is really 0.05
	assert_near(clock.render_time(2.05), 2.05 - 0.05 - Protocol.INTERP_DELAY, 0.0001)
