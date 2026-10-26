class_name SpaceOrbit
extends RefCounted
## Where a rock or pickup is at any server time, from its spawn data alone:
## where it was (origin), how fast it was going (velocity) and when (born).
## Pure two-body motion round the star (pull SpaceStar.GRAVITY / r², no cap):
## circles, ellipses that cross the belts or dive into the star, and escapes.
##
## Solved in closed form with universal variables (Kepler's problem, as in
## Curtis, Orbital Mechanics for Engineering Students, algorithms 3.3-3.4):
## one Newton solve per query, nothing stepped, so a late joiner pays nothing
## for a rock's age. A bound orbit takes the elapsed time modulo its period
## first, so an hour-old rock solves as fast as a new one. Each query starts
## from the last answer (server ticks and client frames ask in small steps)
## and the last one is cached (the server asks about a rock many times a tick).
##
## Every peer solves the same equations from the same spawn data, so they
## agree to far below a pixel. (Inside SpaceStar's MAX_PULL zone the real pull
## on ships is capped; rocks there are about to hit the star anyway.)

const MAX_ITERATIONS: int = 40
const TOLERANCE: float = 1e-9

var origin: Vector2
var velocity: Vector2
var born: float

var _mu: float = SpaceStar.GRAVITY
var _sqrt_mu: float = sqrt(SpaceStar.GRAVITY)
var _r0: Vector2       # relative to the star
var _r0_len: float
var _vr0: float        # radial speed at born
var _alpha: float      # 1 / semi-major axis: > 0 bound, < 0 escaping
var _period: float     # INF unless bound
# Cache: the last time asked, its answer, and its universal anomaly.
var _t: float = NAN
var _pos: Vector2
var _vel: Vector2
var _chi: float = 0.0
var _lap: float = 0.0


func _init(p_origin: Vector2, p_velocity: Vector2, p_born: float) -> void:
	origin = p_origin
	velocity = p_velocity
	born = p_born
	_r0 = origin - SpaceStar.CENTER
	_r0_len = maxf(_r0.length(), 1.0)
	_vr0 = _r0.dot(velocity) / _r0_len
	_alpha = 2.0 / _r0_len - velocity.length_squared() / _mu
	_period = TAU / _sqrt_mu * pow(1.0 / _alpha, 1.5) if _alpha > 1e-12 else INF


## Whether it goes round for ever (an ellipse or a circle), rather than escaping.
func is_bound() -> bool:
	return _period < INF


func position_at(at: float) -> Vector2:
	_solve(at)
	return _pos


func velocity_at(at: float) -> Vector2:
	_solve(at)
	return _vel


func _solve(at: float) -> void:
	if at == _t:
		return
	var dt: float = at - born
	if dt <= 0.0:
		_t = at
		_pos = origin
		_vel = velocity
		_chi = 0.0
		return
	if is_bound():
		var lap: float = floor(dt / _period)
		dt -= lap * _period
		if lap != _lap:
			_lap = lap
			_chi = 0.0   # the last answer was on another lap: start afresh
	_t = at
	var chi: float = _anomaly(dt, _chi)
	_chi = chi
	var z: float = _alpha * chi * chi
	var c: float = stumpff_c(z)
	var s: float = stumpff_s(z)
	var f: float = 1.0 - chi * chi / _r0_len * c
	var g: float = dt - chi * chi * chi / _sqrt_mu * s
	var r: Vector2 = f * _r0 + g * velocity
	var r_len: float = maxf(r.length(), 1.0)
	var fdot: float = _sqrt_mu / (r_len * _r0_len) * (_alpha * chi * chi * chi * s - chi)
	var gdot: float = 1.0 - chi * chi / r_len * c
	_pos = SpaceStar.CENTER + r
	_vel = fdot * _r0 + gdot * velocity


## The universal anomaly chi after `dt`, by Newton's method from `guess`.
func _anomaly(dt: float, guess: float) -> float:
	var chi: float = guess if guess != 0.0 else _sqrt_mu * absf(_alpha) * dt
	if chi == 0.0:
		chi = dt / _r0_len * _sqrt_mu
	for i: int in MAX_ITERATIONS:
		var z: float = _alpha * chi * chi
		var c: float = stumpff_c(z)
		var s: float = stumpff_s(z)
		var k: float = _r0_len * _vr0 / _sqrt_mu
		var f: float = k * chi * chi * c + (1.0 - _alpha * _r0_len) * chi * chi * chi * s \
				+ _r0_len * chi - _sqrt_mu * dt
		var df: float = k * chi * (1.0 - z * s) + (1.0 - _alpha * _r0_len) * chi * chi * c + _r0_len
		var step: float = f / df
		chi -= step
		if absf(step) < TOLERANCE * maxf(1.0, absf(chi)):
			break
	return chi


## Stumpff functions C(z) and S(z), with series near 0 (no cancellation).
static func stumpff_c(z: float) -> float:
	if absf(z) < 1e-6:
		return 0.5 - z / 24.0
	if z > 0.0:
		return (1.0 - cos(sqrt(z))) / z
	return (cosh(sqrt(-z)) - 1.0) / -z


static func stumpff_s(z: float) -> float:
	if absf(z) < 1e-6:
		return 1.0 / 6.0 - z / 120.0
	if z > 0.0:
		var q: float = sqrt(z)
		return (q - sin(q)) / (q * q * q)
	var p: float = sqrt(-z)
	return (sinh(p) - p) / (p * p * p)
