extends Node3D

# Hitscan-with-physics rifle. Each shot:
#   1. Adds recoil pattern offset (with jitter) to aim
#   2. Step-marches a virtual bullet (velocity + gravity drop)
#   3. Schedules damage at impact_time = distance / muzzle_velocity
#   4. Renders a tracer line for the full path

const MUZZLE_VELOCITY := 500.0             # m/s
const BULLET_GRAVITY := 3.0                # m/s^2 (Rust-ish, gentle drop)
const STEP_DT := 0.01                      # trajectory sim step
const MAX_SIM_TIME := 4.0                  # cap (=2km @ 500m/s)
const RECOIL_RESET_DELAY := 0.40           # s of no-fire before pattern index resets
const RECOIL_SMOOTH_RATE := 22.0           # higher = snappier (per-shot kick exp-approaches over ~1/RATE s)
const TRACER_LIFETIME := 0.06              # s

# Weapons that render a red-dot laser sight along the aim ray. Beam +
# dot are constructed lazily in _ready and updated each frame.
const LASER_WEAPONS: Array = ["m700"]
const LASER_RANGE := 800.0
const LASER_DOT_RADIUS := 0.025
const LASER_BEAM_OFFSET_HIP := Vector3(0.06, -0.06, -0.18)   # camera-local muzzle proxy, hipfire
const LASER_BEAM_OFFSET_ADS := Vector3(0.0, -0.04, -0.18)    # centered horizontally while ADS

# Recoil pattern: (yaw_deg, pitch_deg) per shot. Pitch is "kick up" so positive = up.
# AKM: harsher, climbs hard, drifts right.
const RECOIL_PATTERN_AKM: Array[Vector2] = [
	Vector2(-0.15, 1.10),
	Vector2(-0.30, 1.30),
	Vector2(-0.10, 1.50),
	Vector2(-0.45, 1.55),
	Vector2( 0.05, 1.50),
	Vector2(-0.60, 1.45),
	Vector2( 0.15, 1.40),
	Vector2(-0.80, 1.30),
	Vector2( 0.20, 1.25),
	Vector2(-0.95, 1.15),
	Vector2( 0.30, 1.10),
	Vector2(-1.10, 1.00),
]
# M16A2: classic vertical climb, mild horizontal drift.
const RECOIL_PATTERN_M16: Array[Vector2] = [
	Vector2( 0.00, 0.70),
	Vector2( 0.10, 0.85),
	Vector2(-0.10, 1.00),
	Vector2( 0.20, 1.05),
	Vector2(-0.25, 1.00),
	Vector2( 0.35, 0.95),
	Vector2(-0.40, 0.85),
	Vector2( 0.55, 0.80),
	Vector2(-0.60, 0.75),
	Vector2( 0.70, 0.65),
	Vector2(-0.75, 0.65),
	Vector2( 0.85, 0.55),
]
# M60: heavy 7.62 LMG thump, big climb + drift, slower cyclic than M249.
const RECOIL_PATTERN_M60: Array[Vector2] = [
	Vector2(-0.25, 1.40),
	Vector2(-0.45, 1.60),
	Vector2(-0.10, 1.80),
	Vector2(-0.60, 1.90),
	Vector2( 0.10, 1.90),
	Vector2(-0.80, 1.85),
	Vector2( 0.20, 1.80),
	Vector2(-0.95, 1.75),
	Vector2( 0.30, 1.70),
	Vector2(-1.10, 1.65),
	Vector2( 0.40, 1.60),
	Vector2(-1.25, 1.55),
]
# USAS-12 selective-fire shotgun. Gas-operated, slower cyclic than the AA-12,
# with serious 12 gauge climb on full auto.
const RECOIL_PATTERN_USAS12: Array[Vector2] = [
	Vector2( 0.20, 2.60),
	Vector2(-0.30, 2.90),
	Vector2( 0.40, 3.10),
	Vector2(-0.50, 3.10),
	Vector2( 0.60, 3.00),
	Vector2(-0.70, 2.90),
	Vector2( 0.80, 2.80),
	Vector2(-0.90, 2.70),
]
# Colt M1911: heavy .45 ACP pistol. Sharp single-shot kick, recoil index resets
# fast in semi so the early entries do the work.
const RECOIL_PATTERN_M1911: Array[Vector2] = [
	Vector2( 0.10, 1.10),
	Vector2(-0.15, 1.20),
	Vector2( 0.20, 1.25),
	Vector2(-0.25, 1.20),
	Vector2( 0.30, 1.15),
	Vector2(-0.32, 1.10),
	Vector2( 0.34, 1.05),
	Vector2(-0.36, 1.00),
]
# Thompson: WW2 SMG firing .45 ACP. Heavy round = serious vertical climb,
# slower cyclic than smaller-caliber SMGs.
const RECOIL_PATTERN_THOMPSON: Array[Vector2] = [
	Vector2( 0.15, 1.20),
	Vector2(-0.25, 1.40),
	Vector2( 0.35, 1.55),
	Vector2(-0.45, 1.65),
	Vector2( 0.55, 1.65),
	Vector2(-0.65, 1.60),
	Vector2( 0.75, 1.55),
	Vector2(-0.85, 1.50),
	Vector2( 0.95, 1.45),
	Vector2(-1.05, 1.40),
	Vector2( 1.15, 1.35),
	Vector2(-1.25, 1.30),
]
# PPSh-41: WW2 Soviet SMG. Drum-fed 900rpm bash. Mostly vertical with mild
# horizontal wobble from the open-bolt action.
const RECOIL_PATTERN_PPSH: Array[Vector2] = [
	Vector2( 0.20, 1.60),
	Vector2(-0.30, 1.90),
	Vector2( 0.45, 2.10),
	Vector2(-0.55, 2.25),
	Vector2( 0.70, 2.30),
	Vector2(-0.85, 2.30),
	Vector2( 1.00, 2.25),
	Vector2(-1.15, 2.20),
	Vector2( 1.30, 2.15),
	Vector2(-1.45, 2.10),
	Vector2( 1.60, 2.05),
	Vector2(-1.75, 2.00),
]
# Steyr AUG: bullpup 5.56, slightly flatter than M16 (shorter cyclic, balanced
# bullpup geometry). Vertical-leaning with mild horizontal weave.
const RECOIL_PATTERN_AUG: Array[Vector2] = [
	Vector2( 0.00, 0.65),
	Vector2( 0.08, 0.78),
	Vector2(-0.08, 0.92),
	Vector2( 0.18, 0.96),
	Vector2(-0.22, 0.92),
	Vector2( 0.30, 0.88),
	Vector2(-0.35, 0.80),
	Vector2( 0.45, 0.74),
	Vector2(-0.50, 0.70),
	Vector2( 0.60, 0.62),
	Vector2(-0.65, 0.60),
	Vector2( 0.72, 0.52),
]
# SIG STG-57: heavy Swiss battle rifle. Slower cyclic + serious mass tames the
# climb compared to the FAL, but it's still a full-power round.
const RECOIL_PATTERN_STG57: Array[Vector2] = [
	Vector2( 0.10, 1.05),
	Vector2(-0.18, 1.20),
	Vector2( 0.22, 1.30),
	Vector2(-0.30, 1.35),
	Vector2( 0.35, 1.35),
	Vector2(-0.42, 1.30),
	Vector2( 0.48, 1.25),
	Vector2(-0.55, 1.20),
	Vector2( 0.60, 1.15),
	Vector2(-0.68, 1.10),
	Vector2( 0.72, 1.05),
	Vector2(-0.78, 1.00),
]
# FN FAL: full-power 7.62 NATO battle rifle. Heavy climb, drifts left-right
# more than the M60 (handheld vs bipod-fed). Sits between M16 and M60.
const RECOIL_PATTERN_FAL: Array[Vector2] = [
	Vector2( 0.10, 1.20),
	Vector2(-0.20, 1.40),
	Vector2( 0.25, 1.55),
	Vector2(-0.35, 1.65),
	Vector2( 0.40, 1.65),
	Vector2(-0.50, 1.60),
	Vector2( 0.55, 1.55),
	Vector2(-0.65, 1.50),
	Vector2( 0.70, 1.45),
	Vector2(-0.80, 1.40),
	Vector2( 0.85, 1.35),
	Vector2(-0.95, 1.30),
]
# HK G3: roller-delayed blowback. Slightly snappier first shot than the FAL,
# similar sustained climb but with more lateral drift on long bursts.
const RECOIL_PATTERN_G3: Array[Vector2] = [
	Vector2( 0.12, 1.15),
	Vector2(-0.22, 1.35),
	Vector2( 0.30, 1.50),
	Vector2(-0.40, 1.55),
	Vector2( 0.48, 1.55),
	Vector2(-0.58, 1.50),
	Vector2( 0.65, 1.45),
	Vector2(-0.75, 1.40),
	Vector2( 0.82, 1.35),
	Vector2(-0.92, 1.30),
	Vector2( 0.98, 1.25),
	Vector2(-1.05, 1.20),
]
# M14: US service rifle. Higher cyclic than FAL/G3 means steeper climb early
# before the recoil arc settles into the typical battle-rifle drift.
const RECOIL_PATTERN_M14: Array[Vector2] = [
	Vector2( 0.10, 1.30),
	Vector2(-0.20, 1.55),
	Vector2( 0.28, 1.70),
	Vector2(-0.38, 1.75),
	Vector2( 0.45, 1.70),
	Vector2(-0.55, 1.65),
	Vector2( 0.62, 1.60),
	Vector2(-0.72, 1.55),
	Vector2( 0.78, 1.50),
	Vector2(-0.88, 1.45),
	Vector2( 0.94, 1.40),
	Vector2(-1.02, 1.35),
]
# MAC-10: tiny .45 SMG, blistering cyclic, climbs fast.
const RECOIL_PATTERN_MAC10: Array[Vector2] = [
	Vector2( 0.10, 0.90),
	Vector2(-0.20, 1.05),
	Vector2( 0.28, 1.15),
	Vector2(-0.38, 1.20),
	Vector2( 0.45, 1.15),
	Vector2(-0.52, 1.10),
	Vector2( 0.60, 1.05),
	Vector2(-0.68, 1.00),
	Vector2( 0.74, 0.95),
	Vector2(-0.82, 0.92),
]
# Uzi: 9mm, controllable, modest climb with side-to-side drift.
const RECOIL_PATTERN_UZI: Array[Vector2] = [
	Vector2( 0.08, 0.55),
	Vector2(-0.15, 0.62),
	Vector2( 0.22, 0.68),
	Vector2(-0.30, 0.70),
	Vector2( 0.36, 0.68),
	Vector2(-0.42, 0.65),
	Vector2( 0.48, 0.62),
	Vector2(-0.54, 0.60),
	Vector2( 0.60, 0.58),
	Vector2(-0.66, 0.55),
]
# 1903 Springfield: bolt-action, single heavy 30-06 kick.
const RECOIL_PATTERN_M1903: Array[Vector2] = [
	Vector2(-0.18, 3.20),
]
# M1 Garand: semi-auto 30-06, heavy per-shot climb.
const RECOIL_PATTERN_GARAND: Array[Vector2] = [
	Vector2( 0.10, 1.55),
	Vector2(-0.22, 1.65),
	Vector2( 0.32, 1.60),
	Vector2(-0.42, 1.55),
	Vector2( 0.50, 1.50),
	Vector2(-0.60, 1.45),
	Vector2( 0.68, 1.40),
	Vector2(-0.78, 1.35),
]
# BAR: slow-cyclic 30-06 auto rifle, big sustained vertical climb.
const RECOIL_PATTERN_BAR: Array[Vector2] = [
	Vector2( 0.12, 1.55),
	Vector2(-0.25, 1.75),
	Vector2( 0.35, 1.85),
	Vector2(-0.48, 1.85),
	Vector2( 0.55, 1.80),
	Vector2(-0.68, 1.75),
	Vector2( 0.75, 1.70),
	Vector2(-0.88, 1.65),
	Vector2( 0.95, 1.60),
	Vector2(-1.08, 1.55),
]
# KS-23: 23mm pump-action shotgun. One serious per-shell shove.
const RECOIL_PATTERN_KS23: Array[Vector2] = [
	Vector2(-0.30, 3.60),
]
# HK G11 caseless: 4.7×33mm, low impulse per shot, very flat sustained
# climb. The hyperburst dumps 3 rounds before the recoil even reaches the
# shooter, so the per-shot pattern is intentionally tiny.
const RECOIL_PATTERN_G11: Array[Vector2] = [
	Vector2( 0.05, 0.40),
	Vector2(-0.08, 0.45),
	Vector2( 0.10, 0.50),
	Vector2(-0.12, 0.55),
	Vector2( 0.14, 0.55),
	Vector2(-0.16, 0.55),
	Vector2( 0.18, 0.55),
	Vector2(-0.20, 0.50),
	Vector2( 0.22, 0.50),
	Vector2(-0.24, 0.50),
]
# Marlin 1895 .45-70 lever-action: huge per-shot shove, slow follow-up.
const RECOIL_PATTERN_LEVER_4570: Array[Vector2] = [
	Vector2( 0.10, 2.40),
	Vector2(-0.18, 2.55),
	Vector2( 0.22, 2.60),
	Vector2(-0.26, 2.55),
	Vector2( 0.30, 2.50),
	Vector2(-0.34, 2.45),
]
# Single-shot .45-70 hand cannon: one apocalyptic kick.
const RECOIL_PATTERN_PISTOL_4570: Array[Vector2] = [
	Vector2(-0.45, 5.20),
]
# Colt Python .357: stout revolver thump, tight cluster.
const RECOIL_PATTERN_PYTHON: Array[Vector2] = [
	Vector2( 0.10, 1.20),
	Vector2(-0.15, 1.25),
	Vector2( 0.18, 1.20),
	Vector2(-0.22, 1.15),
	Vector2( 0.25, 1.10),
	Vector2(-0.28, 1.05),
]
# Milkor MGL: single launcher thump per pull.
const RECOIL_PATTERN_MGL: Array[Vector2] = [
	Vector2(-0.40, 2.80),
]
# Remington M700: bolt-action sniper, single heavy kick per cycle.
const RECOIL_PATTERN_M700: Array[Vector2] = [
	Vector2(-0.20, 3.40),
]
# M249 SAW: heavy LMG climb, big sustained pitch + wide drift.
const RECOIL_PATTERN_M249: Array[Vector2] = [
	Vector2(-0.20, 1.20),
	Vector2(-0.40, 1.40),
	Vector2(-0.10, 1.55),
	Vector2(-0.55, 1.65),
	Vector2( 0.10, 1.65),
	Vector2(-0.70, 1.60),
	Vector2( 0.20, 1.55),
	Vector2(-0.85, 1.50),
	Vector2( 0.30, 1.45),
	Vector2(-1.00, 1.40),
	Vector2( 0.40, 1.35),
	Vector2(-1.15, 1.30),
]
# M134 Minigun: rotary action distributes impulse so per-round kick is
# tiny, but accuracy is shot to hell by barrel walk + spin precession —
# real recoil is in the bloom, not the climb.
const RECOIL_PATTERN_MINIGUN: Array[Vector2] = [
	Vector2(-0.25, 1.55),
	Vector2(-0.50, 1.75),
	Vector2(-0.15, 1.90),
	Vector2(-0.65, 2.00),
	Vector2( 0.20, 2.00),
	Vector2(-0.85, 1.95),
	Vector2( 0.25, 1.90),
	Vector2(-1.00, 1.85),
	Vector2( 0.40, 1.80),
	Vector2(-1.20, 1.75),
	Vector2( 0.50, 1.70),
	Vector2(-1.35, 1.65),
]
# PM Makarov: small pistol, light upward kick, mild drift.
const RECOIL_PATTERN_MAKAROV: Array[Vector2] = [
	Vector2( 0.05, 0.55),
	Vector2(-0.10, 0.60),
	Vector2( 0.15, 0.65),
	Vector2(-0.18, 0.65),
	Vector2( 0.22, 0.60),
	Vector2(-0.25, 0.58),
	Vector2( 0.28, 0.55),
	Vector2(-0.30, 0.50),
]
# PP-19 Bizon: 9mm helical-mag SMG. Light recoil, mostly vertical with mild drift.
const RECOIL_PATTERN_BIZON: Array[Vector2] = [
	Vector2( 0.50, 0.70),
	Vector2(-0.65, 0.85),
	Vector2( 0.85, 0.95),
	Vector2(-1.00, 1.00),
	Vector2( 1.15, 1.05),
	Vector2(-1.30, 1.05),
	Vector2( 1.45, 1.05),
	Vector2(-1.55, 1.00),
	Vector2( 1.60, 0.95),
	Vector2(-1.65, 0.90),
	Vector2( 1.65, 0.85),
	Vector2(-1.65, 0.80),
]
# SPAS-12: heavy semi-auto shotgun. Big single-shot kick, recoil index resets
# fast in semi so the first few entries do the work.
const RECOIL_PATTERN_SHOTGUN: Array[Vector2] = [
	Vector2( 0.10, 2.20),
	Vector2(-0.15, 2.30),
	Vector2( 0.20, 2.40),
	Vector2(-0.25, 2.45),
	Vector2( 0.30, 2.45),
	Vector2(-0.35, 2.40),
]
# P90: high-cyclic PDW. Light per-shot pitch, mild horizontal weave. Climbs
# faster than the Bizon but still flatter than full-power rifles.
const RECOIL_PATTERN_P90: Array[Vector2] = [
	Vector2( 0.20, 0.65),
	Vector2(-0.30, 0.75),
	Vector2( 0.40, 0.85),
	Vector2(-0.50, 0.90),
	Vector2( 0.60, 0.90),
	Vector2(-0.70, 0.90),
	Vector2( 0.80, 0.85),
	Vector2(-0.85, 0.80),
	Vector2( 0.90, 0.75),
	Vector2(-0.95, 0.70),
	Vector2( 1.00, 0.65),
	Vector2(-1.00, 0.60),
]
# MP5: between AK and M16 vertically, but very horizontal — wide left/right swings.
const RECOIL_PATTERN_MP5: Array[Vector2] = [
	Vector2( 0.40, 0.55),
	Vector2(-0.55, 0.70),
	Vector2( 0.70, 0.80),
	Vector2(-0.85, 0.85),
	Vector2( 1.00, 0.90),
	Vector2(-1.15, 0.95),
	Vector2( 1.25, 0.95),
	Vector2(-1.30, 0.90),
	Vector2( 1.35, 0.85),
	Vector2(-1.40, 0.80),
	Vector2( 1.45, 0.75),
	Vector2(-1.50, 0.70),
]
const RECOIL_JITTER_DEG := 0.12
const CROUCH_RECOIL_MULT := 0.5
const HIP_RECOIL_MULT := 1.30      # extra kick when not ADS
const HIP_BLOOM_DEG := 1.8         # cone half-angle of random spread when hip-firing
const MOVE_BLOOM_DEG := 1.2        # extra bloom while moving on foot (uncrouched)
const AIR_BLOOM_DEG := 2.5         # extra bloom while airborne
const MOVE_SPEED_THRESHOLD := 0.5  # m/s of horizontal velocity to count as "moving"

const BURST_COUNT := 3
const BURST_COOLDOWN := 0.22           # gap after a burst completes before next burst can start
const BURST_RPM_MULT := 1.10           # 10% faster intra-burst cyclic
const BURST_RECOIL_MULT := 0.90        # 10% less recoil per burst shot
const BURST_BLOOM_MULT := 0.90         # 10% less bloom while burst-firing
const RELOAD_TIME := 2.0                # default if a profile omits reload_time
const FIRE_PITCH_MIN := 0.94
const FIRE_PITCH_MAX := 1.06
const FIRE_VOL_DB := -4.0
const FIRE_HOLD_TIME := 0.22    # full-volume window before fade kicks in
const FIRE_FADE_TIME := 0.32    # fade-out length, kills the tail echo
const FIRE_FADE_DB := -50.0
const FIRE_VOICES := 4
const IMPACT_DIRT_PATH := "res://assets/audio/impact_dirt.ogg"
const IMPACT_CONCRETE_PATH := "res://assets/audio/impact_concrete.ogg"
const CASING_PATH := "res://assets/audio/casing.ogg"
const CASING_DELAY_MIN := 0.35
const CASING_DELAY_MAX := 0.55
const CASING_VOL_DB := -24.0
const CASING_PITCH_MIN := 0.92
const CASING_PITCH_MAX := 1.10
const CASING_VOICES := 6
const RELOAD_SOUND_PATH := "res://assets/audio/reload.ogg"
const RELOAD_VOL_DB := -10.0
const IMPACT_VOL_DB := -6.0
const IMPACT_PITCH_MIN := 0.92
const IMPACT_PITCH_MAX := 1.08
const IMPACT_VOICES := 6
enum FireMode { SEMI, BURST, AUTO }

const PROFILES := {
	"akm": {
		"name": "AKM",
		"mag_size": 30,
		"rpm": 600.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mmSoviet.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_AKM,
		"bloom_mult": 1.0,
		"ammo_id": "ammo_762x39",
		"reload_time": 4.4,
		"pullout_time": 1.0,
	},
	"sks": {
		"name": "SKS",
		"mag_size": 10,
		"rpm": 380.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mmSoviet.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_AKM,
		"bloom_mult": 0.85,
		"ammo_id": "ammo_762x39",
		"reload_time": 4.4,
		"pullout_time": 1.15,
	},
	"m16a2": {
		"name": "M16A2",
		"mag_size": 30,
		"rpm": 700.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK556mm.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_M16,
		"bloom_mult": 1.0,
		"ammo_id": "ammo_556nato",
		"reload_time": 4.0,
		"pullout_time": 1.5,
	},
	"bizon": {
		"name": "PP-19 Bizon",
		"mag_size": 64,
		"rpm": 700.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_PPBizon.ogg"],
		"fire_hold": 0.18,
		"fire_fade": 0.26,
		"recoil_pattern": RECOIL_PATTERN_BIZON,
		"bloom_mult": 1.4,
		"ammo_id": "ammo_9x18",
		"reload_time": 4.4,
		"pullout_time": 1.2,
	},
	"mp5sd": {
		"name": "MP5",
		"mag_size": 30,
		"rpm": 800.0,
		"modes": [FireMode.BURST, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_MP5Type.ogg"],
		"fire_hold": 0.08,
		"fire_fade": 0.18,
		"fire_vol_db": 2.0,
		"recoil_pattern": RECOIL_PATTERN_MP5,
		"bloom_mult": 2.2,
		"ammo_id": "ammo_9mm",
		"reload_time": 4.0,
		"pullout_time": 1.6,
	},
	"m249": {
		"name": "M249",
		"mag_size": 100,
		"rpm": 800.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK556mm_BeltA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_M249,
		"bloom_mult": 1.6,
		"ammo_id": "ammo_556nato",
		"reload_time": 7.5,
		"pullout_time": 1.8,
	},
	"m60": {
		"name": "M60",
		"mag_size": 100,
		"rpm": 600.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_M60,
		"bloom_mult": 1.7,
		"ammo_id": "ammo_762nato",
		"reload_time": 7.5,
		"pullout_time": 1.9,
	},
	"minigun": {
		"name": "M134 Minigun",
		"mag_size": 300,
		"rpm": 1500.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mm_BeltA.ogg"],
		"fire_hold": 0.06,
		"fire_fade": 0.16,
		"recoil_pattern": RECOIL_PATTERN_MINIGUN,
		"bloom_mult": 3.5,
		"ammo_id": "ammo_762nato",
		"reload_time": 12.0,
		"pullout_time": 2.5,
	},
	"makarov": {
		"name": "PM Makarov",
		"mag_size": 8,
		"rpm": 240.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK9mm_Modern.ogg"],
		"fire_hold": 0.10,
		"fire_fade": 0.18,
		"recoil_pattern": RECOIL_PATTERN_MAKAROV,
		"bloom_mult": 1.6,
		"ammo_id": "ammo_9x18",
		"reload_time": 2.9,
		"pullout_time": 0.5,
	},
	"usas12": {
		"name": "USAS-12",
		"mag_size": 20,
		"rpm": 360.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_AA12.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_USAS12,
		"bloom_mult": 1.0,
		"ammo_id": "ammo_12ga",
		"ammo_ids": ["ammo_12ga", "ammo_12ga_slug"],
		"reload_time": 4.0,
		"pullout_time": 1.7,
		"shell_impact_path": "res://assets/audio/shellimpact.wav",
		"shell_impact_delay_min": 0.30,
		"shell_impact_delay_max": 0.55,
		"shell_impact_pitch_min": 0.90,
		"shell_impact_pitch_max": 1.12,
		"shell_impact_vol_db": -18.0,
	},
	"shotgun_combat": {
		"name": "SPAS-12",
		"mag_size": 8,
		"rpm": 240.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK12GaA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_SHOTGUN,
		"bloom_mult": 1.2,
		"ammo_id": "ammo_12ga",
		"ammo_ids": ["ammo_12ga", "ammo_12ga_slug"],
		"per_round_reload": true,
		"reload_time_per_round": 0.85,
		"shell_impact_path": "res://assets/audio/shellimpact.wav",
		"shell_impact_delay_min": 0.45,
		"shell_impact_delay_max": 0.75,
		"shell_impact_pitch_min": 0.90,
		"shell_impact_pitch_max": 1.12,
		"shell_impact_vol_db": -18.0,
		"pullout_time": 1.6,
		"pump_reload_path": "res://assets/audio/Sub_GTEKShotgunPump.ogg",
		"pump_reload_vol_db": -6.0,
		"pump_reload_pitch_min": 0.96,
		"pump_reload_pitch_max": 1.04,
	},
	"p90": {
		"name": "FN P90",
		"mag_size": 50,
		"rpm": 900.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_P90B.ogg"],
		"fire_hold": 0.14,
		"fire_fade": 0.22,
		"recoil_pattern": RECOIL_PATTERN_P90,
		"bloom_mult": 1.5,
		"ammo_id": "ammo_57x28",
		"reload_time": 3.6,
		"pullout_time": 1.2,
	},
	"m700": {
		"name": "Remington M700",
		"mag_size": 5,
		"rpm": 50.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mm.ogg"],
		"fire_hold": 0.30,
		"fire_fade": 0.45,
		"recoil_pattern": RECOIL_PATTERN_M700,
		"bloom_mult": 0.6,
		"ammo_id": "ammo_762nato",
		"reload_time": 4.2,
		"scope": true,
		"ads_fov": 13.0,
		"bolt_unscope_time": 0.85,
		"bolt_sound_path": "res://assets/audio/Sub_GTEKBoltAction.ogg",
		"bolt_delay": 0.20,
		"bolt_pitch_min": 0.96,
		"bolt_pitch_max": 1.04,
		"bolt_vol_db": -4.0,
		"pullout_time": 1.0,
	},
	"m1911": {
		"name": "Colt M1911",
		"mag_size": 7,
		"rpm": 240.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK45ACP.ogg"],
		"fire_hold": 0.10,
		"fire_fade": 0.18,
		"recoil_pattern": RECOIL_PATTERN_M1911,
		"bloom_mult": 1.4,
		"ammo_id": "ammo_45acp",
		"reload_time": 2.5,
		"pullout_time": 0.55,
	},
	"mac10": {
		"name": "MAC-10",
		"mag_size": 30,
		"rpm": 1100.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK45ACPSMG.ogg"],
		"fire_hold": 0.16,
		"fire_fade": 0.24,
		"recoil_pattern": RECOIL_PATTERN_MAC10,
		"bloom_mult": 2.2,
		"ammo_id": "ammo_45acp",
		"reload_time": 2.6,
		"pullout_time": 0.9,
	},
	"uzi": {
		"name": "Uzi",
		"mag_size": 32,
		"rpm": 600.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_PPBizon.ogg"],
		"fire_hold": 0.18,
		"fire_fade": 0.28,
		"recoil_pattern": RECOIL_PATTERN_UZI,
		"bloom_mult": 1.4,
		"ammo_id": "ammo_9mm",
		"reload_time": 3.0,
		"pullout_time": 1.0,
	},
	"m1903": {
		"name": "1903 Springfield",
		"mag_size": 5,
		"rpm": 50.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mm.ogg"],
		"fire_hold": 0.30,
		"fire_fade": 0.45,
		"recoil_pattern": RECOIL_PATTERN_M1903,
		"bloom_mult": 0.7,
		"ammo_id": "ammo_3006",
		"reload_time": 4.5,
		"ads_fov": 35.0,
		"bolt_unscope_time": 0.85,
		"bolt_sound_path": "res://assets/audio/Sub_GTEKBoltAction.ogg",
		"bolt_delay": 0.20,
		"bolt_pitch_min": 0.96,
		"bolt_pitch_max": 1.04,
		"bolt_vol_db": -4.0,
		"pullout_time": 1.1,
	},
	"garand": {
		"name": "M1 Garand",
		"mag_size": 8,
		"rpm": 360.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mm.ogg"],
		"fire_hold": 0.24,
		"fire_fade": 0.36,
		"recoil_pattern": RECOIL_PATTERN_GARAND,
		"bloom_mult": 1.0,
		"ammo_id": "ammo_3006",
		"reload_time": 3.0,
		"pullout_time": 1.2,
	},
	"bar": {
		"name": "BAR",
		"mag_size": 20,
		"rpm": 550.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.34,
		"recoil_pattern": RECOIL_PATTERN_BAR,
		"bloom_mult": 1.2,
		"ammo_id": "ammo_3006",
		"reload_time": 4.0,
		"pullout_time": 1.6,
	},
	"ks23": {
		"name": "KS-23",
		"mag_size": 4,
		"rpm": 60.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK12GaA.ogg"],
		"fire_hold": 0.28,
		"fire_fade": 0.42,
		"recoil_pattern": RECOIL_PATTERN_KS23,
		"bloom_mult": 1.3,
		"ammo_id": "ammo_23x75",
		"per_round_reload": true,
		"reload_time_per_round": 1.0,
		"shell_impact_path": "res://assets/audio/shellimpact.wav",
		"shell_impact_delay_min": 0.50,
		"shell_impact_delay_max": 0.85,
		"shell_impact_pitch_min": 0.85,
		"shell_impact_pitch_max": 1.05,
		"shell_impact_vol_db": -16.0,
		"pullout_time": 1.4,
		"pump_reload_path": "res://assets/audio/Sub_GTEKShotgunPump.ogg",
		"pump_reload_vol_db": -6.0,
		"pump_reload_pitch_min": 0.90,
		"pump_reload_pitch_max": 1.00,
	},
	"g11": {
		"name": "HK G11",
		"mag_size": 50,
		"rpm": 600.0,
		"modes": [FireMode.SEMI, FireMode.BURST, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_M16A.ogg"],
		"fire_hold": 0.18,
		"fire_fade": 0.26,
		"recoil_pattern": RECOIL_PATTERN_G11,
		"bloom_mult": 0.85,
		"ammo_id": "ammo_47x33",
		"reload_time": 3.4,
		"pullout_time": 1.2,
		# 2160 RPM hyperburst — three rounds dump in ~83ms total.
		"burst_rpm_mult": 3.6,
		"burst_fire_sound": "res://assets/audio/Shot_GTEK473mm.ogg",
		"burst_end_kick_deg": Vector2(0.4, 5.0),
	},
	"lever_4570": {
		"name": "Marlin 1895",
		"mag_size": 6,
		"rpm": 80.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.28,
		"fire_fade": 0.42,
		"recoil_pattern": RECOIL_PATTERN_LEVER_4570,
		"bloom_mult": 0.85,
		"ammo_id": "ammo_4570",
		"per_round_reload": true,
		"reload_time_per_round": 0.70,
		"pullout_time": 1.2,
	},
	"pistol_4570": {
		"name": "Hand Cannon",
		"mag_size": 1,
		"rpm": 60.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK762mm.ogg"],
		"fire_hold": 0.32,
		"fire_fade": 0.50,
		"recoil_pattern": RECOIL_PATTERN_PISTOL_4570,
		"bloom_mult": 1.5,
		"ammo_id": "ammo_4570",
		"reload_time": 2.4,
		"pullout_time": 0.9,
	},
	"python": {
		"name": "Colt Python",
		"mag_size": 6,
		"rpm": 200.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK45ACP.ogg"],
		"fire_hold": 0.16,
		"fire_fade": 0.26,
		"recoil_pattern": RECOIL_PATTERN_PYTHON,
		"bloom_mult": 1.3,
		"ammo_id": "ammo_357",
		"per_round_reload": true,
		"reload_time_per_round": 0.55,
		"has_speedloader": true,
		"speedloader_time": 2.0,
		"pullout_time": 0.7,
	},
	"thompson": {
		"name": "Thompson",
		"mag_size": 30,
		"rpm": 700.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK45ACPSMG.ogg"],
		"fire_hold": 0.20,
		"fire_fade": 0.30,
		"recoil_pattern": RECOIL_PATTERN_THOMPSON,
		"bloom_mult": 1.6,
		"ammo_id": "ammo_45acp",
		"reload_time": 4.0,
		"pullout_time": 1.5,
	},
	"ppsh41": {
		"name": "PPSh-41",
		"mag_size": 71,
		"rpm": 1000.0,
		"modes": [FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_PPBizon.ogg"],
		"fire_hold": 0.18,
		"fire_fade": 0.26,
		"recoil_pattern": RECOIL_PATTERN_PPSH,
		"bloom_mult": 2.4,
		"ammo_id": "ammo_762x25",
		"reload_time": 4.5,
		"pullout_time": 1.4,
	},
	"aug": {
		"name": "Steyr AUG",
		"mag_size": 30,
		"rpm": 660.0,
		"modes": [FireMode.SEMI, FireMode.BURST, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK556mm.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_AUG,
		"bloom_mult": 0.95,
		"ammo_id": "ammo_556nato",
		"reload_time": 4.0,
		"pullout_time": 1.4,
		"scope": true,
		"ads_fov": 35.0,
	},
	"stg57": {
		"name": "STG-57",
		"mag_size": 24,
		"rpm": 520.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_STG57,
		"bloom_mult": 0.95,
		"ammo_id": "ammo_75x55",
		"reload_time": 4.0,
		"pullout_time": 1.5,
	},
	"g3": {
		"name": "HK G3",
		"mag_size": 20,
		"rpm": 600.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_G3,
		"bloom_mult": 1.05,
		"ammo_id": "ammo_762nato",
		"reload_time": 3.6,
		"pullout_time": 1.2,
	},
	"m14": {
		"name": "M14",
		"mag_size": 20,
		"rpm": 750.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_M14,
		"bloom_mult": 1.15,
		"ammo_id": "ammo_762nato",
		"reload_time": 3.6,
		"pullout_time": 1.2,
	},
	"fal": {
		"name": "FN FAL",
		"mag_size": 20,
		"rpm": 620.0,
		"modes": [FireMode.SEMI, FireMode.AUTO],
		"fire_sounds": ["res://assets/audio/Shot_GTEK_FALA.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_FAL,
		"bloom_mult": 1.1,
		"ammo_id": "ammo_762nato",
		"reload_time": 3.8,
		"pullout_time": 1.2,
	},
	"mgl": {
		"name": "MGL",
		"mag_size": 6,
		"rpm": 180.0,
		"modes": [FireMode.SEMI],
		"fire_sounds": ["res://assets/audio/Shot_GTEK40mmGL.ogg"],
		"fire_hold": 0.22,
		"fire_fade": 0.32,
		"recoil_pattern": RECOIL_PATTERN_MGL,
		"bloom_mult": 1.0,
		"projectile": true,
		"projectile_velocity": 75.0,
		"ammo_id": "ammo_40mm",
		"per_round_reload": true,
		"reload_time_per_round": 1.0,
		"no_shell_impact": true,
		"pullout_time": 1.0,
	},
}
const DEFAULT_PULLOUT_TIME := 1.0
const WEAPON_ORDER := ["akm", "sks", "m16a2", "aug", "fal", "g3", "m14", "stg57", "bar", "garand", "m1903", "bizon", "mp5sd", "ppsh41", "thompson", "uzi", "mac10", "p90", "makarov", "m1911", "m700", "m249", "m60", "minigun", "mgl", "shotgun_combat", "ks23", "usas12", "lever_4570", "pistol_4570", "python", "g11"]
const GRENADE_SCRIPT := preload("res://grenade.gd")
const Items = preload("res://items.gd")

@export var camera_path: NodePath
@export var player_path: NodePath
@export var inventory_path: NodePath

var _camera: Camera3D
var _player: Node    # CharacterBody3D w/ _yaw/_pitch
var _inventory: Node
var _last_fire_time := -1000.0
var _recoil_index := 0
# Per-instance last-used fire mode so swapping back restores it. Keyed by
# inventory uid so two of the same weapon track independently.
var _saved_fire_modes: Dictionary = {}
# Per-instance current magazine count so swapping doesn't dupe ammo or refill
# mid-fight. Also keyed by uid.
var _saved_ammo: Dictionary = {}
# Per-instance selected ammo id (multi-ammo weapons like SPAS-12). Keyed by uid.
var _saved_selected_ammo: Dictionary = {}
# Currently selected ammo id for the equipped weapon. Defaults to profile's ammo_id.
var _selected_ammo: String = ""
# uid of the currently equipped instance (0 = unknown / direct-key equip).
var _current_uid: int = 0
var _rng := RandomNumberGenerator.new()
# Smoothed recoil: shots add to *target*; _process exp-approaches it and applies the per-frame delta to the player view.
var _target_yaw := 0.0
var _target_pitch := 0.0
var _applied_yaw := 0.0
var _applied_pitch := 0.0
# Recoil-control HUD telemetry. Tracks one "session" — a burst of fire bookended
# by RECOIL_SESSION_RESET seconds of idle. Anchored to the player's view at
# session start; per-shot history records cumulative kick (rad) and drift (rad)
# of the camera from the anchor at shot time. Score = 1 - drift/kick.
const RECOIL_SESSION_RESET := 0.6
var _rec_session_active: bool = false
var _rec_anchor_yaw: float = 0.0
var _rec_anchor_pitch: float = 0.0
var _rec_kick_total: Vector2 = Vector2.ZERO
var _rec_history: Array = []
var _rec_frozen_drift: Vector2 = Vector2.ZERO
var _rec_frozen: bool = false
var _current_weapon: String = "akm"
var _equipped: bool = false   # false = empty hands; gates fire/reload/recoil decay. Player spawns unarmed.
# Time (Time.get_ticks_msec()/1000.0) at which the current weapon
# finishes its pullout/raise animation. Fire is gated until then so
# every equip pays the per-weapon raise cost.
var _pullout_until: float = 0.0
# Laser sight nodes (top_level so we can drive them in world space).
var _laser_dot: MeshInstance3D
var _laser_beam: MeshInstance3D
var _laser_beam_im: ImmediateMesh
var _laser_beam_mat: StandardMaterial3D
var _profile: Dictionary = {}
# Minigun spin throttle. 0 = idle, 1 = fully spun (firing enabled).
# Driven by RMB hold while the minigun is equipped; spins back down on
# release. Player.gd reads this to scale move speed + block jump.
const MINIGUN_SPINUP_TIME: float = 1.2
const MINIGUN_SPINDOWN_TIME: float = 1.8
var _minigun_spin_t: float = 0.0
var _fire_streams: Dictionary = {}     # weapon key -> Array[AudioStream]
var _burst_fire_streams: Dictionary = {}  # weapon key -> AudioStream (one per burst)
var _ammo := 0
var _fire_mode: FireMode = FireMode.AUTO
var _burst_remaining := 0
var _burst_cooldown_until := -1000.0
var _reloading := false
var _reload_remaining := 0.0
var _reload_amount := 0   # rounds queued for transfer when reload finishes
var _reload_total := 0.0  # full-cycle time for HUD progress (per-round = window)
var _speedloader_active := false  # true while a hold-R revolver reload is in flight
var _audio_voices: Array[AudioStreamPlayer3D] = []
var _audio_tweens: Array[Tween] = []
var _audio_idx := 0
var _fire_stream_list: Array = []
var _impact_streams: Dictionary = {}    # "dirt"/"concrete" -> AudioStream
var _impact_voices: Array[AudioStreamPlayer3D] = []
var _impact_idx := 0
var _casing_stream: AudioStream
var _casing_voices: Array[AudioStreamPlayer3D] = []
var _casing_idx := 0
# Per-weapon "spent shell hits the floor" stream pool. Keyed by weapon profile
# key, value is Array[AudioStream] (one variant picked at random per shot).
# Empty/missing entry means the weapon plays no shell-impact sound.
var _shell_impact_streams: Dictionary = {}
var _shell_impact_voices: Array[AudioStreamPlayer3D] = []
var _shell_impact_idx := 0
const SHELL_IMPACT_VOICES := 4
# Bolt-cycle sound (currently just M700). Single voice per weapon — bolt
# action only fires one round at a time so we don't need a pool.
var _bolt_streams: Dictionary = {}
var _bolt_voice: AudioStreamPlayer3D = null
# Default brass-casing impact set used by every weapon that doesn't override
# (SPAS-12 ships its own shellimpact.wav; MGL opts out via no_shell_impact).
const DEFAULT_BRASS_PATHS: Array = [
	"res://assets/audio/brassimpact_1a.wav",
	"res://assets/audio/brassimpact_1b.wav",
	"res://assets/audio/brassimpact_1c.wav",
	"res://assets/audio/brassimpact_1d.wav",
	"res://assets/audio/brassimpact_1e.wav",
]
const DEFAULT_BRASS_DELAY_MIN := 0.30
const DEFAULT_BRASS_DELAY_MAX := 0.55
const DEFAULT_BRASS_PITCH_MIN := 0.90
const DEFAULT_BRASS_PITCH_MAX := 1.12
const DEFAULT_BRASS_VOL_DB := -18.0
var _reload_player: AudioStreamPlayer3D
var _reload_stream: AudioStream
# Per-shell pump sound for per-round reloads (SPAS-12 etc). Stream + player
# are keyed off the current weapon so loading a shell triggers the right
# pump for whichever shotgun is in hand.
var _pump_streams: Dictionary = {}
var _pump_player: AudioStreamPlayer3D

# Active attachment mods on the currently equipped instance — accumulated from
# every attachment installed in the weapon's slots. Recomputed on equip + when
# the inventory changes the equipped instance's attachments.
var _active_mods: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	if camera_path != NodePath():
		_camera = get_node(camera_path)
	if player_path != NodePath():
		_player = get_node(player_path)
	if inventory_path != NodePath():
		_inventory = get_node(inventory_path)
	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.changed.connect(_recompute_active_mods)
	if _inventory != null and _inventory.has_signal("mag_invalidated"):
		_inventory.mag_invalidated.connect(_on_mag_invalidated)
	_setup_audio()
	_setup_laser()
	_apply_weapon(_current_weapon)

func _apply_weapon(key: String, uid: int = 0) -> void:
	if not PROFILES.has(key):
		return
	# Stash outgoing instance's mode + ammo so swapping back restores both.
	# Falls back to the weapon key when there's no uid (direct equip).
	var out_key: Variant = _current_uid if _current_uid != 0 else _current_weapon
	if PROFILES.has(_current_weapon):
		_saved_fire_modes[out_key] = _fire_mode
		_saved_ammo[out_key] = _ammo
		_saved_selected_ammo[out_key] = _selected_ammo
	_current_weapon = key
	_current_uid = uid
	_profile = PROFILES[key]
	var in_key: Variant = uid if uid != 0 else key
	_ammo = int(_saved_ammo.get(in_key, _profile.mag_size))
	# Restore last-used mode if we have one (and it's still legal for this weapon).
	var modes: Array = _profile.modes
	var saved_mode = _saved_fire_modes.get(in_key, null)
	if saved_mode != null and modes.has(saved_mode):
		_fire_mode = saved_mode
	else:
		_fire_mode = modes[0]
	# Restore selected ammo if remembered + still compatible; otherwise default
	# to profile's primary ammo_id.
	var compat: Array = get_compatible_ammo_ids()
	var saved_ammo = _saved_selected_ammo.get(in_key, "")
	if saved_ammo != "" and compat.has(String(saved_ammo)):
		_selected_ammo = String(saved_ammo)
	else:
		_selected_ammo = String(_profile.get("ammo_id", ""))
	_burst_remaining = 0
	_recoil_index = 0
	_target_yaw = _applied_yaw
	_target_pitch = _applied_pitch
	# Swap the fire-sound stream(s) on every voice in the pool. Stream is picked
	# per-shot in _play_fire_sound when the weapon has multiple variants.
	_fire_stream_list = _fire_streams.get(key, [])
	for v in _audio_voices:
		v.stop()
		v.stream = _fire_stream_list[0] if not _fire_stream_list.is_empty() else null

func equip(key: String, uid: int = 0) -> void:
	if not PROFILES.has(key):
		return
	# Same instance already armed: nothing to do.
	if key == _current_weapon and uid == _current_uid and _equipped:
		return
	# Cancel any in-flight reload — swapping aborts it (no ammo was consumed
	# yet; _finish_reload only fires on completion). Otherwise the new weapon
	# silently never gets equipped.
	if _reloading:
		_reloading = false
		_reload_remaining = 0.0
		_reload_amount = 0
		if _reload_player != null:
			_reload_player.stop()
	if key != _current_weapon or uid != _current_uid:
		_apply_weapon(key, uid)
	# Persisted-mag carry-over from a world drop: if the inventory instance
	# we're equipping carries a "mag" / "selected_ammo" / "fire_mode" field
	# (set when the weapon was dropped), use those instead of the saved-by-
	# uid defaults — the new uid has no matching _saved_ammo entry yet.
	if uid != 0 and _inventory != null and _inventory.has_method("get_instance"):
		var inst: Dictionary = _inventory.get_instance(uid)
		if not inst.is_empty():
			if inst.has("mag"):
				_ammo = clampi(int(inst["mag"]), 0, get_mag_size())
				_saved_ammo[uid] = _ammo
			if inst.has("selected_ammo") and String(inst["selected_ammo"]) != "":
				var sa: String = String(inst["selected_ammo"])
				if get_compatible_ammo_ids().has(sa):
					_selected_ammo = sa
					_saved_selected_ammo[uid] = sa
			if inst.has("fire_mode"):
				var fm: int = int(inst["fire_mode"])
				if _profile.modes.has(fm):
					_fire_mode = fm
					_saved_fire_modes[uid] = fm
	_equipped = true
	_recompute_active_mods()
	# After mods may have changed mag_size, clamp current ammo so a 75-round
	# drum equipped while holding 30 doesn't artificially overflow when reload
	# math runs.
	_ammo = clampi(_ammo, 0, get_mag_size())
	# Start the pullout cooldown. Reading the profile here (after
	# _apply_weapon swap) so per-weapon values land correctly.
	var pullout: float = float(_profile.get("pullout_time", DEFAULT_PULLOUT_TIME))
	_pullout_until = Time.get_ticks_msec() / 1000.0 + pullout

# Magazine attachment was removed/swapped down — dump the loaded rounds
# back to inventory and zero the mag for that uid so the player can't keep
# firing rounds the new mag never held.
func _on_mag_invalidated(uid: int) -> void:
	if _inventory == null:
		return
	var inst: Dictionary = _inventory.get_instance(uid)
	if inst.is_empty():
		return
	var weapon_key: String = String(inst.item_id)
	if not PROFILES.has(weapon_key):
		return
	var ammo_id: String = ""
	if uid == _current_uid:
		ammo_id = _selected_ammo
	if ammo_id == "":
		ammo_id = String(inst.get("selected_ammo", ""))
	if ammo_id == "":
		ammo_id = String(_saved_selected_ammo.get(uid, ""))
	if ammo_id == "":
		ammo_id = String(PROFILES[weapon_key].get("ammo_id", ""))
	var rounds: int = 0
	if uid == _current_uid:
		rounds = _ammo
		_ammo = 0
	else:
		rounds = int(inst.get("mag", _saved_ammo.get(uid, 0)))
		inst["mag"] = 0
	_saved_ammo[uid] = 0
	if rounds > 0 and ammo_id != "" and _inventory.has_method("grant"):
		_inventory.grant(ammo_id, rounds)

# Roll up every attachment's mods dict for the currently-equipped instance into
# a single dict the runtime queries. mag_size = max of installed mags; *_mult
# values multiply; flag/value fields use last-write-wins.
func _recompute_active_mods() -> void:
	var prev_mag_size: int = get_mag_size()
	_active_mods = {}
	if not _equipped or _current_uid == 0 or _inventory == null:
		return
	if not _inventory.has_method("get_attachments"):
		return
	var atts: Dictionary = _inventory.get_attachments(_current_uid)
	for slot_id in atts.keys():
		var att_id: String = String(atts[slot_id])
		var mods: Dictionary = Items.attachment_mods(att_id)
		for k in mods.keys():
			var key: String = String(k)
			var v = mods[k]
			if key == "mag_size":
				_active_mods[key] = max(int(_active_mods.get(key, 0)), int(v))
			elif key.ends_with("_mult"):
				_active_mods[key] = float(_active_mods.get(key, 1.0)) * float(v)
			else:
				_active_mods[key] = v
	# Mag-size changed mid-reload: abort the current cycle and restart so the
	# new capacity (and remaining-rounds math) takes effect immediately.
	if _reloading and get_mag_size() != prev_mag_size:
		_reloading = false
		_reload_remaining = 0.0
		_reload_amount = 0
		_speedloader_active = false
		if _reload_player != null:
			_reload_player.stop()
		if _bolt_voice != null:
			_bolt_voice.stop()
		_start_reload()

# Snapshot the live state of the weapon instance keyed by `uid`. Used by
# the drop path so the world pickup carries the player's current mag,
# selected ammo, and fire mode rather than resetting on re-pickup.
func capture_state(uid: int) -> Dictionary:
	if uid == 0:
		return {}
	if uid == _current_uid:
		return {
			"mag": _ammo,
			"selected_ammo": _selected_ammo,
			"fire_mode": int(_fire_mode),
		}
	if _saved_ammo.has(uid):
		return {
			"mag": int(_saved_ammo[uid]),
			"selected_ammo": String(_saved_selected_ammo.get(uid, "")),
			"fire_mode": int(_saved_fire_modes.get(uid, FireMode.SEMI)),
		}
	return {}

func unequip() -> void:
	_equipped = false
	_burst_remaining = 0
	# Stop any in-flight fire-sound voices so the gun doesn't keep ringing.
	for v in _audio_voices:
		v.stop()
	if _reload_player != null:
		_reload_player.stop()
	_reloading = false

func is_equipped() -> bool:
	return _equipped

func get_current_weapon() -> String:
	return _current_weapon

func _setup_audio() -> void:
	# .import is gitignored on this source-pull repo, so res:// won't resolve the
	# .ogg via GD.Load. Load the file straight off disk at runtime.
	for key in WEAPON_ORDER:
		var paths: Array = PROFILES[key].get("fire_sounds", [])
		var streams: Array = []
		for path in paths:
			var s: AudioStream = _load_wav(path)
			if s != null:
				streams.append(s)
		_fire_streams[key] = streams
		var bpath: String = String(PROFILES[key].get("burst_fire_sound", ""))
		if bpath != "":
			var bs: AudioStream = _load_wav(bpath)
			if bs != null:
				_burst_fire_streams[key] = bs
	_fire_stream_list = _fire_streams.get(_current_weapon, [])
	# Voice pool so fast-fire shots don't restart each other mid-fade —
	# the fade-out on shot N keeps ringing while shot N+1 starts on a fresh voice.
	for i in range(FIRE_VOICES):
		var p := AudioStreamPlayer3D.new()
		p.stream = _fire_stream_list[0] if not _fire_stream_list.is_empty() else null
		p.volume_db = FIRE_VOL_DB
		p.unit_size = 14.0
		p.max_distance = 120.0
		p.bus = "Master"
		add_child(p)
		_audio_voices.append(p)
		_audio_tweens.append(null)
	# Impact streams (loaded at runtime — same .import-gitignored reason).
	_impact_streams["dirt"] = _load_wav(IMPACT_DIRT_PATH)
	_impact_streams["concrete"] = _load_wav(IMPACT_CONCRETE_PATH)
	# Roving impact voices live on the scene root so they play at the world
	# position of the hit, not at the gun.
	for i in range(IMPACT_VOICES):
		var ip := AudioStreamPlayer3D.new()
		ip.bus = "Master"
		ip.volume_db = IMPACT_VOL_DB
		ip.unit_size = 14.0
		ip.max_distance = 120.0
		_impact_voices.append(ip)
	# Casing voices live on the player so the clink follows them around.
	_casing_stream = _load_wav(CASING_PATH)
	for i in range(CASING_VOICES):
		var cp := AudioStreamPlayer3D.new()
		cp.stream = _casing_stream
		cp.bus = "Master"
		cp.volume_db = CASING_VOL_DB
		cp.unit_size = 4.0
		cp.max_distance = 18.0
		add_child(cp)
		_casing_voices.append(cp)
	# Spent-shell impact streams. Each weapon gets a list of variants; one is
	# picked at random per shot. Profile order: explicit shell_impact_paths >
	# single shell_impact_path > default brass set. no_shell_impact opts out
	# entirely (e.g. MGL — 40mm grenades don't drop brass).
	for key in WEAPON_ORDER:
		var prof: Dictionary = PROFILES[key]
		if bool(prof.get("no_shell_impact", false)):
			continue
		var paths: Array = []
		var multi: Array = prof.get("shell_impact_paths", [])
		var single: String = String(prof.get("shell_impact_path", ""))
		if not multi.is_empty():
			paths = multi
		elif single != "":
			paths = [single]
		else:
			paths = DEFAULT_BRASS_PATHS
		var streams: Array = []
		for p in paths:
			var s: AudioStream = _load_wav(String(p))
			if s != null:
				streams.append(s)
		if not streams.is_empty():
			_shell_impact_streams[key] = streams
	# Voice pool lives on the player (gun) so the clatter follows them.
	for i in range(SHELL_IMPACT_VOICES):
		var sp := AudioStreamPlayer3D.new()
		sp.bus = "Master"
		sp.unit_size = 4.0
		sp.max_distance = 22.0
		add_child(sp)
		_shell_impact_voices.append(sp)
	# Bolt-cycle streams (M700 etc). One stream per weapon profile that
	# defines bolt_sound_path; shared single voice on the weapon.
	for key in WEAPON_ORDER:
		var bp: String = String(PROFILES[key].get("bolt_sound_path", ""))
		if bp == "":
			continue
		var bs: AudioStream = _load_wav(bp)
		if bs != null:
			_bolt_streams[key] = bs
	if not _bolt_streams.is_empty():
		_bolt_voice = AudioStreamPlayer3D.new()
		_bolt_voice.bus = "Master"
		_bolt_voice.unit_size = 5.0
		_bolt_voice.max_distance = 20.0
		add_child(_bolt_voice)
	# Pump-action shell-load streams (SPAS-12). One stream per profile that
	# defines pump_reload_path; played per shell loaded.
	for key in WEAPON_ORDER:
		var pp: String = String(PROFILES[key].get("pump_reload_path", ""))
		if pp == "":
			continue
		var ps: AudioStream = _load_wav(pp)
		if ps != null:
			_pump_streams[key] = ps
	if not _pump_streams.is_empty():
		_pump_player = AudioStreamPlayer3D.new()
		_pump_player.bus = "Master"
		_pump_player.unit_size = 5.0
		_pump_player.max_distance = 20.0
		add_child(_pump_player)
	# Reload sound — single voice on the weapon, plays start of reload.
	_reload_stream = _load_wav(RELOAD_SOUND_PATH)
	_reload_player = AudioStreamPlayer3D.new()
	_reload_player.stream = _reload_stream
	_reload_player.bus = "Master"
	_reload_player.volume_db = RELOAD_VOL_DB
	_reload_player.unit_size = 6.0
	_reload_player.max_distance = 25.0
	add_child(_reload_player)

func _load_wav(res_path: String) -> AudioStream:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var ext: String = res_path.get_extension().to_lower()
	if ext == "wav":
		return AudioStreamWAV.load_from_file(abs_path)
	return AudioStreamOggVorbis.load_from_file(abs_path)

# --- Multi-ammo support ---------------------------------------------------
# Most weapons feed a single cartridge (profile.ammo_id). The SPAS-12 accepts
# both buckshot and slugs and the player picks via the radial reload menu.
func get_compatible_ammo_ids() -> Array:
	var ids: Array = _profile.get("ammo_ids", [])
	if not ids.is_empty():
		return ids
	var single: String = String(_profile.get("ammo_id", ""))
	return [single] if single != "" else []

func get_selected_ammo() -> String:
	if _selected_ammo != "":
		return _selected_ammo
	return String(_profile.get("ammo_id", ""))

func set_selected_ammo(id: String) -> void:
	if id == "":
		return
	if not get_compatible_ammo_ids().has(id):
		return
	_selected_ammo = id

# Dump every loaded round back into inventory under the *current* selected
# ammo. Used when switching cartridge types — can't mix shells in the same
# tube, so empty before refilling.
func unload_mag() -> void:
	if _ammo <= 0:
		return
	var ammo_id := get_selected_ammo()
	if _inventory != null and ammo_id != "" and _inventory.has_method("add"):
		_inventory.add(ammo_id, _ammo)
	_ammo = 0

func get_reserve_ammo() -> int:
	if _inventory == null:
		return 0
	var ammo_id := get_selected_ammo()
	if ammo_id == "":
		return 0
	return int(_inventory.counts.get(ammo_id, 0))

# Public entry point for reload — player handles input and calls this.
func start_reload() -> void:
	_start_reload()

func has_speedloader() -> bool:
	return _equipped and bool(_profile.get("has_speedloader", false))

# Force a full-mag batch reload, bypassing per-round behavior. Used for
# revolver speedloaders where hold-R loads every chamber at once.
func start_reload_speedloader() -> void:
	if not _equipped:
		return
	if _reloading:
		# Cancel any in-progress per-round chain so the speedloader takes over.
		_reloading = false
		_reload_remaining = 0.0
		_reload_amount = 0
		if _reload_player != null: _reload_player.stop()
		if _bolt_voice != null: _bolt_voice.stop()
	if _ammo >= get_mag_size():
		return
	var need: int = get_mag_size() - _ammo
	var avail: int = get_reserve_ammo()
	var take: int = min(need, avail)
	if take <= 0:
		return
	_reload_amount = take
	_reloading = true
	_burst_remaining = 0
	_reload_total = float(_profile.get("speedloader_time", 2.0))
	_reload_remaining = _reload_total
	# Use the bolt voice line for the speedloader click — clean, no extra asset.
	var bolt_stream: AudioStream = _bolt_streams.get(_current_weapon, null)
	if bolt_stream != null and _bolt_voice != null:
		var bmin: float = float(_profile.get("bolt_pitch_min", 0.97))
		var bmax: float = float(_profile.get("bolt_pitch_max", 1.03))
		_bolt_voice.stop()
		_bolt_voice.stream = bolt_stream
		_bolt_voice.pitch_scale = _rng.randf_range(bmin, bmax)
		_bolt_voice.volume_db = float(_profile.get("bolt_vol_db", -4.0))
		_bolt_voice.play()
	_speedloader_active = true

func _start_reload() -> void:
	if _reloading or _ammo >= get_mag_size():
		return
	var need: int = get_mag_size() - _ammo
	var avail: int = get_reserve_ammo()
	var take: int = min(need, avail)
	if take <= 0:
		return
	_reload_amount = take
	_reloading = true
	_burst_remaining = 0
	if bool(_profile.get("per_round_reload", false)):
		# Each round loads independently; firing cancels the chain.
		_reload_total = float(_profile.get("reload_time_per_round", 1.0))
		_reload_remaining = _reload_total
	else:
		_reload_total = float(_profile.get("reload_time", RELOAD_TIME))
		_reload_remaining = _reload_total
		if _reload_player != null and _reload_stream != null:
			_reload_player.stop()
			_reload_player.play()
		var bolt_stream: AudioStream = _bolt_streams.get(_current_weapon, null)
		if bolt_stream != null and _bolt_voice != null:
			var bmin: float = float(_profile.get("bolt_pitch_min", 0.97))
			var bmax: float = float(_profile.get("bolt_pitch_max", 1.03))
			_bolt_voice.stop()
			_bolt_voice.stream = bolt_stream
			_bolt_voice.pitch_scale = _rng.randf_range(bmin, bmax)
			_bolt_voice.volume_db = float(_profile.get("bolt_vol_db", -4.0))
			_bolt_voice.play()

func _finish_reload() -> void:
	var ammo_id := get_selected_ammo()
	if _inventory != null and ammo_id != "" and _reload_amount > 0:
		# Re-clamp against reserve at finish time in case inventory changed mid-reload.
		var actual: int = min(_reload_amount, int(_inventory.counts.get(ammo_id, 0)))
		if actual > 0:
			_inventory.remove(ammo_id, actual)
			_ammo += actual
	_reload_amount = 0

# Per-round reload tick: pull a single round from inventory into the mag.
func _load_one_round() -> void:
	var ammo_id := get_selected_ammo()
	if _inventory == null or ammo_id == "":
		return
	if int(_inventory.counts.get(ammo_id, 0)) <= 0:
		_reload_amount = 0
		return
	_inventory.remove(ammo_id, 1)
	_ammo += 1
	_reload_amount -= 1
	var pump_stream: AudioStream = _pump_streams.get(_current_weapon, null)
	if pump_stream != null and _pump_player != null:
		var pmin: float = float(_profile.get("pump_reload_pitch_min", 0.97))
		var pmax: float = float(_profile.get("pump_reload_pitch_max", 1.03))
		_pump_player.stream = pump_stream
		_pump_player.pitch_scale = _rng.randf_range(pmin, pmax)
		_pump_player.volume_db = float(_profile.get("pump_reload_vol_db", -6.0))
		_pump_player.play()

# Spent shotgun shell hitting the floor — fires after a randomized delay so it
# lands cleanly in the post-shot quiet, with pitch + delay variation per shot.
func _schedule_shell_impact() -> void:
	var streams: Array = _shell_impact_streams.get(_current_weapon, [])
	if streams.is_empty() or _shell_impact_voices.is_empty():
		return
	var stream: AudioStream = streams[_rng.randi() % streams.size()]
	var delay: float = _rng.randf_range(
		float(_profile.get("shell_impact_delay_min", DEFAULT_BRASS_DELAY_MIN)),
		float(_profile.get("shell_impact_delay_max", DEFAULT_BRASS_DELAY_MAX)),
	)
	var pitch: float = _rng.randf_range(
		float(_profile.get("shell_impact_pitch_min", DEFAULT_BRASS_PITCH_MIN)),
		float(_profile.get("shell_impact_pitch_max", DEFAULT_BRASS_PITCH_MAX)),
	)
	var vol: float = float(_profile.get("shell_impact_vol_db", DEFAULT_BRASS_VOL_DB))
	var idx: int = _shell_impact_idx
	_shell_impact_idx = (_shell_impact_idx + 1) % _shell_impact_voices.size()
	var voice: AudioStreamPlayer3D = _shell_impact_voices[idx]
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if not is_instance_valid(voice):
			return
		voice.stream = stream
		voice.pitch_scale = pitch
		voice.volume_db = vol
		voice.play()
	)

func _schedule_bolt() -> void:
	var stream: AudioStream = _bolt_streams.get(_current_weapon, null)
	if stream == null or _bolt_voice == null:
		return
	var delay: float = float(_profile.get("bolt_delay", 0.18))
	var pitch: float = _rng.randf_range(
		float(_profile.get("bolt_pitch_min", 0.97)),
		float(_profile.get("bolt_pitch_max", 1.03)),
	)
	var vol: float = float(_profile.get("bolt_vol_db", -4.0))
	var voice: AudioStreamPlayer3D = _bolt_voice
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if not is_instance_valid(voice):
			return
		voice.stream = stream
		voice.pitch_scale = pitch
		voice.volume_db = vol
		voice.play()
	)

func _schedule_casing() -> void:
	if _casing_stream == null or _casing_voices.is_empty():
		return
	var delay: float = _rng.randf_range(CASING_DELAY_MIN, CASING_DELAY_MAX)
	var pitch: float = _rng.randf_range(CASING_PITCH_MIN, CASING_PITCH_MAX)
	var idx: int = _casing_idx
	_casing_idx = (_casing_idx + 1) % _casing_voices.size()
	var voice: AudioStreamPlayer3D = _casing_voices[idx]
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if not is_instance_valid(voice):
			return
		voice.pitch_scale = pitch
		voice.play()
	)

func _play_fire_sound() -> void:
	if _fire_stream_list.is_empty() or _audio_voices.is_empty():
		return
	_play_fire_sound_with(_fire_stream_list[_rng.randi() % _fire_stream_list.size()])

func _play_fire_sound_with(stream: AudioStream) -> void:
	if stream == null or _audio_voices.is_empty():
		return
	var idx: int = _audio_idx
	_audio_idx = (_audio_idx + 1) % _audio_voices.size()
	var voice: AudioStreamPlayer3D = _audio_voices[idx]
	# Cancel any in-flight fade on this voice before reusing it.
	var prev: Tween = _audio_tweens[idx]
	if prev != null and prev.is_valid():
		prev.kill()
	voice.stream = stream
	voice.volume_db = float(_profile.get("fire_vol_db", FIRE_VOL_DB))
	voice.pitch_scale = _rng.randf_range(FIRE_PITCH_MIN, FIRE_PITCH_MAX)
	voice.play()
	# Hold full volume briefly, then fade the tail to silence and stop the voice.
	var hold: float = float(_profile.get("fire_hold", FIRE_HOLD_TIME))
	var fade: float = float(_profile.get("fire_fade", FIRE_FADE_TIME))
	var t: Tween = create_tween()
	t.tween_interval(hold)
	t.tween_property(voice, "volume_db", FIRE_FADE_DB, fade)
	t.tween_callback(voice.stop)
	_audio_tweens[idx] = t

func is_ads() -> bool:
	return _player != null and _player.has_method("is_ads") and _player.is_ads()

func is_minigun_equipped() -> bool:
	return _current_weapon == "minigun"

func get_minigun_spin() -> float:
	return _minigun_spin_t

# True if the equipped weapon should render the scope overlay when ADS.
func has_scope() -> bool:
	if bool(_active_mods.get("scope", false)):
		return true
	return bool(_profile.get("scope", false))

# Per-weapon ADS FOV override (sniper scopes are much narrower than 55°).
func get_ads_fov(default_fov: float) -> float:
	if _active_mods.has("ads_fov"):
		return float(_active_mods["ads_fov"])
	return float(_profile.get("ads_fov", default_fov))

# Bolt-action rifles force the player out of ADS for the cycle duration so
# they have to re-shoulder between shots. Returns true while that lock is
# active.
func is_ads_locked() -> bool:
	var lock_time: float = float(_profile.get("bolt_unscope_time", 0.0))
	if lock_time <= 0.0:
		return false
	return (Time.get_ticks_msec() / 1000.0) - _last_fire_time < lock_time

func get_weapon_name() -> String:
	return _profile.get("name", "?")

func get_ammo() -> int:
	return _ammo

func get_mag_size() -> int:
	if _active_mods.has("mag_size"):
		return int(_active_mods["mag_size"])
	return int(_profile.get("mag_size", 0))

func _fire_interval() -> float:
	var rpm: float = float(_profile.get("rpm", 600.0))
	return 60.0 / rpm if rpm > 0.0 else 0.1

func _available_modes() -> Array:
	return _profile.get("modes", [FireMode.AUTO])

func get_fire_mode_name() -> String:
	match _fire_mode:
		FireMode.SEMI: return "SEMI"
		FireMode.BURST: return "BURST"
		FireMode.AUTO: return "AUTO"
	return "?"

func is_reloading() -> bool:
	return _reloading

func get_reload_progress() -> float:
	if not _reloading or _reload_total <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_remaining / _reload_total, 0.0, 1.0)

func get_current_bloom_deg() -> float:
	if _player == null:
		return 0.0
	var ads: bool = _player.has_method("is_ads") and _player.is_ads()
	var bloom_deg: float = 0.0
	if not ads:
		bloom_deg += HIP_BLOOM_DEG
	var crouched: bool = _player.has_method("is_crouched") and _player.is_crouched()
	var horiz_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving: bool = horiz_speed > MOVE_SPEED_THRESHOLD
	var airborne: bool = not _player.is_on_floor()
	if moving and not crouched:
		bloom_deg += MOVE_BLOOM_DEG
	if airborne:
		bloom_deg += AIR_BLOOM_DEG
	bloom_deg *= float(_profile.get("bloom_mult", 1.0))
	bloom_deg *= float(_active_mods.get("bloom_mult", 1.0))
	if _fire_mode == FireMode.BURST:
		bloom_deg *= BURST_BLOOM_MULT
	return bloom_deg

func _process(delta: float) -> void:
	_update_laser()
	# Freeze all weapon input + recoil decay while the inventory menu or pie
	# is up.
	if _player != null and _player.has_method("is_menu_open") and _player.is_menu_open():
		return
	if _player != null and _player.has_method("is_pie_open") and _player.is_pie_open():
		return
	# Empty hands — no fire, no reload, no recoil decay (decay would still
	# run, but there's nothing meaningful to decay since no shots add to it).
	if not _equipped:
		return

	var now := Time.get_ticks_msec() / 1000.0

	if Input.is_action_just_pressed("cycle_fire_mode"):
		var modes: Array = _available_modes()
		var idx: int = modes.find(_fire_mode)
		if idx < 0:
			idx = -1
		idx = (idx + 1) % modes.size()
		_fire_mode = modes[idx]
		_burst_remaining = 0

	if _reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			if _speedloader_active:
				# Speedloader: dump every chambered round at once, then exit.
				_reload_remaining = 0.0
				_reloading = false
				_speedloader_active = false
				_finish_reload()
			elif bool(_profile.get("per_round_reload", false)):
				# Transfer one round, then either start the next round's window
				# or end the reload chain.
				_load_one_round()
				if _reload_amount > 0 and _ammo < get_mag_size():
					_reload_remaining += _reload_total
				else:
					_reload_remaining = 0.0
					_reloading = false
					_reload_amount = 0
			else:
				_reload_remaining = 0.0
				_reloading = false
				_finish_reload()

	# Minigun spin-up driven by RMB hold. Spins back down on release. Cannot
	# spin while reloading (mag swap interrupts the throttle). Only the
	# minigun owns this state; other weapons keep it at 0.
	if _current_weapon == "minigun":
		var want_spin: bool = Input.is_action_pressed("ads") and not _reloading and now >= _pullout_until
		var spin_rate: float = (1.0 / MINIGUN_SPINUP_TIME) if want_spin else -(1.0 / MINIGUN_SPINDOWN_TIME)
		_minigun_spin_t = clamp(_minigun_spin_t + spin_rate * delta, 0.0, 1.0)
	else:
		_minigun_spin_t = 0.0

	# Decide whether to fire this frame based on mode. Per-round reload only
	# allows fire if at least one round has finished loading — partway through
	# the current round's window the shell isn't seated yet, so trigger does
	# nothing. Once a round is in, firing cancels the rest of the chain.
	var per_round: bool = bool(_profile.get("per_round_reload", false))
	var per_round_fireable: bool = per_round and _ammo > 0
	var want_fire := false
	if not _reloading or per_round_fireable:
		match _fire_mode:
			FireMode.SEMI:
				want_fire = Input.is_action_just_pressed("fire")
			FireMode.AUTO:
				want_fire = Input.is_action_pressed("fire")
			FireMode.BURST:
				if Input.is_action_just_pressed("fire") and _burst_remaining == 0 and now >= _burst_cooldown_until:
					_burst_remaining = BURST_COUNT
				want_fire = _burst_remaining > 0
	if want_fire and _reloading and per_round_fireable:
		_reloading = false
		_reload_remaining = 0.0
		_reload_amount = 0
		_speedloader_active = false

	var interval: float = _fire_interval()
	if _fire_mode == FireMode.BURST:
		# Per-profile override lets weapons like the G11 (hyperburst) crank
		# intra-burst cyclic well past the global default.
		interval /= float(_profile.get("burst_rpm_mult", BURST_RPM_MULT))
	# Minigun must be fully spun before any round leaves the barrel.
	var minigun_ready: bool = _current_weapon != "minigun" or _minigun_spin_t >= 1.0
	if want_fire and _ammo > 0 and now - _last_fire_time >= interval and now >= _pullout_until and minigun_ready:
		_fire(now)
		_ammo -= 1
		if _fire_mode == FireMode.BURST:
			_burst_remaining = max(_burst_remaining - 1, 0)
			if _burst_remaining == 0:
				_burst_cooldown_until = now + BURST_COOLDOWN
		if _ammo == 0:
			# Auto-reload when mag empties.
			_start_reload()

	if now - _last_fire_time > RECOIL_RESET_DELAY:
		_recoil_index = 0
	# Once the session has been idle past the reset window, freeze the final
	# drift sample so the HUD pin stops chasing the player's resting aim.
	if _rec_session_active and not _rec_frozen and now - _last_fire_time > RECOIL_SESSION_RESET:
		_rec_frozen = true
		_rec_frozen_drift = Vector2(_player._yaw - _rec_anchor_yaw, _player._pitch - _rec_anchor_pitch)
	_apply_smoothed_recoil(delta)

func _apply_smoothed_recoil(delta: float) -> void:
	if _player == null:
		return
	# Frame-rate-independent exponential approach.
	var alpha: float = 1.0 - exp(-RECOIL_SMOOTH_RATE * delta)
	var new_yaw: float = lerpf(_applied_yaw, _target_yaw, alpha)
	var new_pitch: float = lerpf(_applied_pitch, _target_pitch, alpha)
	var dy: float = new_yaw - _applied_yaw
	var dp: float = new_pitch - _applied_pitch
	if absf(dy) < 1e-6 and absf(dp) < 1e-6:
		return
	_player._yaw += dy
	_player._pitch = clampf(_player._pitch + dp, -1.4, 1.4)
	_player.rotation.y = _player._yaw
	_player._camera.rotation.x = _player._pitch
	_applied_yaw = new_yaw
	_applied_pitch = new_pitch

func _spawn_projectile(origin: Vector3, dir: Vector3) -> void:
	var g: Node3D = Node3D.new()
	g.set_script(GRENADE_SCRIPT)
	get_tree().current_scene.add_child(g)
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	var muzzle_vel: float = float(_profile.get("projectile_velocity", 75.0))
	# Spawn slightly out from camera so the round doesn't immediately raycast into the player.
	g.call("setup", origin + dir * 0.4, dir * muzzle_vel, ex)

func _fire(now: float) -> void:
	var prev_fire := _last_fire_time
	_last_fire_time = now
	if _camera == null or _player == null:
		return

	var ads: bool = _player.has_method("is_ads") and _player.is_ads()
	# Open or continue a recoil-tracking session for the HUD panel.
	if not _rec_session_active or now - prev_fire > RECOIL_SESSION_RESET:
		_rec_anchor_yaw = _player._yaw
		_rec_anchor_pitch = _player._pitch
		_rec_kick_total = Vector2.ZERO
		_rec_history.clear()
		_rec_session_active = true
		_rec_frozen = false
		_rec_frozen_drift = Vector2.ZERO

	# Bullet leaves at the *current* aim. The new kick goes into the smoothed
	# target — camera will lerp toward it over the next few frames, so the
	# crosshair drifts up smoothly instead of teleporting per shot.
	var pattern: Array = _profile.get("recoil_pattern", RECOIL_PATTERN_M16)
	var pat: Vector2 = pattern[_recoil_index % pattern.size()]
	var jitter_yaw = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var jitter_pitch = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var mult: float = 1.0
	if _player.has_method("is_crouched") and _player.is_crouched():
		mult *= CROUCH_RECOIL_MULT
		mult *= float(_active_mods.get("recoil_crouch_mult", 1.0))
	if not ads:
		mult *= HIP_RECOIL_MULT
	if _fire_mode == FireMode.BURST:
		mult *= BURST_RECOIL_MULT
	var kick_yaw_rad: float = deg_to_rad(pat.x + jitter_yaw) * mult
	var kick_pitch_rad: float = deg_to_rad(pat.y + jitter_pitch) * mult
	# Telemetry: capture player's drift from anchor BEFORE adding this shot's
	# kick — that records how the player handled the *previous* shots' recoil.
	_rec_history.append({
		"kick": _rec_kick_total,
		"drift": Vector2(_player._yaw - _rec_anchor_yaw, _player._pitch - _rec_anchor_pitch),
	})
	_rec_kick_total += Vector2(kick_yaw_rad, kick_pitch_rad)
	_target_yaw += kick_yaw_rad
	_target_pitch += kick_pitch_rad
	# Burst-end extra kick: apply once on the final shot of a burst so the
	# camera shoves hard between bursts (G11 hyperburst impulse).
	if _fire_mode == FireMode.BURST and _burst_remaining == 1:
		var end_kick: Vector2 = _profile.get("burst_end_kick_deg", Vector2.ZERO)
		if end_kick != Vector2.ZERO:
			var jx: float = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
			var ek_yaw: float = deg_to_rad(end_kick.x + jx) * mult
			var ek_pitch: float = deg_to_rad(end_kick.y) * mult
			_rec_kick_total += Vector2(ek_yaw, ek_pitch)
			_target_yaw += ek_yaw
			_target_pitch += ek_pitch
	_recoil_index += 1

	# Burst with a one-per-burst sound: play override on the first shot,
	# stay silent on the trailing shots so the burst lands as a single audio hit.
	var burst_stream: AudioStream = _burst_fire_streams.get(_current_weapon, null)
	if _fire_mode == FireMode.BURST and burst_stream != null:
		if _burst_remaining == BURST_COUNT:
			_play_fire_sound_with(burst_stream)
		# else: silent — let the first sound carry the whole burst.
	else:
		_play_fire_sound()
	# Casing clink disabled — too harsh when stacked under full-auto fire.
	# Spent shell/brass impact — every weapon that registered streams in
	# _setup_audio (SPAS-12 = unique shellimpact, everything else = default
	# brass set; MGL opted out via no_shell_impact).
	if _shell_impact_streams.has(_current_weapon):
		_schedule_shell_impact()
	if _bolt_streams.has(_current_weapon):
		_schedule_bolt()

	# Sim trajectory from camera origin in camera-forward direction.
	var origin: Vector3 = _camera.global_transform.origin
	var cam_basis: Basis = _camera.global_transform.basis
	var dir: Vector3 = -cam_basis.z
	dir = dir.normalized()

	# Projectile weapons (grenade launcher etc) spawn a physical round and bail.
	if bool(_profile.get("projectile", false)):
		_spawn_projectile(origin, dir)
		return

	# Bloom matches the on-screen crosshair (hip + movement + airborne).
	var bloom_deg: float = get_current_bloom_deg()
	# Pellet count + per-pellet spread come from the cartridge def (slugs = 1
	# pellet, buckshot = 8). Each pellet picks its own random spread cone on
	# top of the shared bloom cone.
	var ammo_id := get_selected_ammo()
	var pellets: int = max(1, Items.ammo_pellets(ammo_id))
	var pellet_spread: float = Items.ammo_pellet_spread_deg(ammo_id) * float(_active_mods.get("pellet_spread_mult", 1.0))
	for i in range(pellets):
		var pdir: Vector3 = dir
		var total_spread_deg: float = bloom_deg + pellet_spread
		if total_spread_deg > 0.0:
			var ang: float = sqrt(_rng.randf()) * deg_to_rad(total_spread_deg)
			var theta: float = _rng.randf() * TAU
			var local_offset := Vector3(sin(ang) * cos(theta), sin(ang) * sin(theta), -cos(ang))
			pdir = (cam_basis * local_offset).normalized()
		_fire_pellet(origin, pdir)

func _fire_pellet(origin: Vector3, pdir: Vector3) -> void:
	var muzzle_speed: float = MUZZLE_VELOCITY * float(_active_mods.get("velocity_mult", 1.0))
	var vel: Vector3 = pdir * muzzle_speed
	var gravity := Vector3(0.0, -BULLET_GRAVITY, 0.0)

	var space := get_world_3d().direct_space_state
	var pos := origin
	var t := 0.0
	var hit_pos := Vector3.ZERO
	var hit_normal := Vector3.UP
	var hit_collider: Object = null
	var has_hit := false
	while t < MAX_SIM_TIME:
		var next_pos := pos + vel * STEP_DT + gravity * 0.5 * STEP_DT * STEP_DT
		vel += gravity * STEP_DT
		var q := PhysicsRayQueryParameters3D.create(pos, next_pos)
		var ex: Array[RID] = []
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r and r.has("position"):
			hit_pos = r.position
			hit_normal = r.get("normal", Vector3.UP)
			hit_collider = r.get("collider", null)
			has_hit = true
			break
		pos = next_pos
		t += STEP_DT

	if not has_hit:
		hit_pos = pos

	var distance := origin.distance_to(hit_pos)
	var impact_delay := distance / muzzle_speed
	_spawn_tracer(origin, hit_pos)
	if has_hit:
		var material := _classify_material(hit_collider)
		_schedule_impact(hit_pos, hit_normal, material, impact_delay, hit_collider)
		_schedule_damage(hit_collider, impact_delay, distance)

func _schedule_damage(collider: Object, delay: float, distance: float) -> void:
	if collider == null:
		return
	# Walk up the parent chain looking for either a `take_damage` method
	# (dummies, future enemies) or the destructible meta-flag stamped by
	# main_bootstrap on placed objects. The collider itself is usually a
	# StaticBody3D or MeshInstance3D nested inside the prop's root Node3D.
	var target: Node = _find_damageable(collider)
	if target == null:
		return
	var dmg: int = Items.ammo_damage_at(get_selected_ammo(), distance)
	dmg = int(round(float(dmg) * float(_active_mods.get("damage_mult", 1.0))))
	if dmg <= 0:
		return
	if delay <= 0.0:
		_apply_damage(target, dmg)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if is_instance_valid(target):
			_apply_damage(target, dmg)
	)

func _find_damageable(collider: Object) -> Node:
	var n: Node = collider as Node
	while n != null:
		if n.has_method("take_damage"):
			return n
		if n.has_meta("destructible") and bool(n.get_meta("destructible")):
			return n
		n = n.get_parent()
	return null

func _apply_damage(target: Node, dmg: int) -> void:
	if target.has_method("take_damage"):
		target.call("take_damage", dmg)
		return
	# Meta-driven destructible: decrement HP, free the prop when it hits 0.
	var hp: int = int(target.get_meta("hp", 0))
	hp = max(hp - dmg, 0)
	target.set_meta("hp", hp)
	if hp <= 0:
		target.queue_free()

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	mat.disable_receive_shadows = true
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)

	var timer := get_tree().create_timer(TRACER_LIFETIME)
	timer.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())

func _classify_material(collider: Object) -> String:
	if collider == null:
		return "concrete"
	# Walk up looking for a take_damage method — those are flesh (dummies,
	# enemies). Destructible-meta props don't count as flesh; they get the
	# default concrete impact since they're crates/boxes/etc.
	var t: Node = collider as Node
	while t != null:
		if t.has_method("take_damage"):
			return "flesh"
		t = t.get_parent()
	var n: String = ""
	if collider is Node:
		n = (collider as Node).name
	if n == "Ground":
		return "dirt"
	if n.begins_with("Wall"):
		return "concrete"
	return "concrete"

func _schedule_impact(world_pos: Vector3, normal: Vector3, material: String, delay: float, collider: Object = null) -> void:
	if delay <= 0.0:
		_apply_impact(world_pos, normal, material, collider)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _apply_impact(world_pos, normal, material, collider))

const BULLET_HOLE_HOLD := 4.0
const BULLET_HOLE_FADE := 2.5
const BULLET_HOLE_SIZE := 0.08

func _apply_impact(world_pos: Vector3, normal: Vector3, material: String, collider: Object = null) -> void:
	# Impact sounds disabled — broken clips, regenerating.
	_spawn_impact_particles(world_pos, normal, material)
	# Skip bullet-hole decals on flesh — they'd just float in the air once
	# the target moves, and look weird stuck to a body anyway.
	if material != "flesh":
		_spawn_bullet_hole(world_pos, normal, material, collider)

func _find_movable_host(collider: Object) -> Node3D:
	# Walk up the tree to find a RigidBody3D / VehicleBody3D / CharacterBody3D
	# the decal can hang under so it tracks the moving body.
	var n := collider as Node
	while n != null:
		if n is RigidBody3D or n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return null

func _spawn_bullet_hole(world_pos: Vector3, normal: Vector3, material: String, collider: Object = null) -> void:
	var n: Vector3 = normal.normalized()
	var quad := QuadMesh.new()
	quad.size = Vector2(BULLET_HOLE_SIZE, BULLET_HOLE_SIZE)
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match material:
		"dirt":
			mat.albedo_color = Color(0.08, 0.05, 0.03, 0.95)
		"concrete":
			mat.albedo_color = Color(0.10, 0.10, 0.10, 0.95)
		_:
			mat.albedo_color = Color(0.05, 0.05, 0.05, 0.95)
	quad.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Parent the decal to whatever the bullet actually hit so it follows
	# moving objects (vehicles, destructibles). Falls back to scene root
	# only when the collider can't host children.
	var parent: Node = _find_damageable(collider)
	if parent == null or not (parent is Node3D):
		var n_node := _find_movable_host(collider)
		parent = n_node if n_node != null else get_tree().current_scene
	parent.add_child(mi)
	# Orient quad so its +Z faces along the surface normal, then nudge it
	# slightly off the surface to avoid z-fighting.
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(-n, up), world_pos + n * 0.005)

	var tween := create_tween()
	tween.tween_interval(BULLET_HOLE_HOLD)
	tween.tween_property(mat, "albedo_color:a", 0.0, BULLET_HOLE_FADE)
	tween.tween_callback(func(): if is_instance_valid(mi): mi.queue_free())

func _play_impact_sound(world_pos: Vector3, material: String) -> void:
	if not _impact_streams.has(material):
		return
	var stream: AudioStream = _impact_streams[material]
	if stream == null or _impact_voices.is_empty():
		return
	var idx: int = _impact_idx
	_impact_idx = (_impact_idx + 1) % _impact_voices.size()
	var voice: AudioStreamPlayer3D = _impact_voices[idx]
	if voice.is_inside_tree():
		voice.get_parent().remove_child(voice)
	get_tree().current_scene.add_child(voice)
	voice.global_position = world_pos
	voice.stream = stream
	voice.pitch_scale = _rng.randf_range(IMPACT_PITCH_MIN, IMPACT_PITCH_MAX)
	voice.volume_db = IMPACT_VOL_DB
	voice.play()

func _spawn_impact_particles(world_pos: Vector3, normal: Vector3, material: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	match material:
		"dirt":
			mat.albedo_color = Color(0.42, 0.28, 0.18, 1.0)
		"concrete":
			mat.albedo_color = Color(0.85, 0.83, 0.78, 1.0)
		"flesh":
			mat.albedo_color = Color(0.55, 0.05, 0.05, 1.0)
		_:
			mat.albedo_color = Color(0.7, 0.7, 0.7, 1.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = mat

	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36 if material == "flesh" else 22
	p.lifetime = 0.7 if material == "flesh" else 0.6
	p.local_coords = false
	p.direction = normal.normalized()
	p.spread = 55.0 if material == "flesh" else 42.0
	p.initial_velocity_min = 2.4 if material == "flesh" else 1.8
	p.initial_velocity_max = 5.5 if material == "flesh" else 4.5
	p.gravity = Vector3(0.0, -9.0 if material == "flesh" else -7.0, 0.0)
	p.scale_amount_min = 0.5 if material == "flesh" else 0.6
	p.scale_amount_max = 1.2 if material == "flesh" else 1.4
	p.damping_min = 1.0
	p.damping_max = 3.0
	# Cast/receive flags off so unshaded specks don't blow out shadow maps.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	get_tree().current_scene.add_child(p)
	p.global_position = world_pos + normal.normalized() * 0.02   # nudge off the surface
	# Trigger emission after the node is in the tree + positioned.
	p.restart()
	p.emitting = true

	var timer := get_tree().create_timer(p.lifetime + 0.4)
	timer.timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _setup_laser() -> void:
	# Dot — small unshaded sphere, no depth test so it stays visible
	# against bright surfaces.
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = LASER_DOT_RADIUS
	dot_mesh.height = LASER_DOT_RADIUS * 2.0
	dot_mesh.radial_segments = 12
	dot_mesh.rings = 6
	var dot_mat := StandardMaterial3D.new()
	dot_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1.0, 0.05, 0.05, 1.0)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 0.0, 0.0, 1.0)
	dot_mat.emission_energy_multiplier = 4.0
	dot_mat.no_depth_test = true
	dot_mat.disable_receive_shadows = true
	_laser_dot = MeshInstance3D.new()
	_laser_dot.mesh = dot_mesh
	_laser_dot.material_override = dot_mat
	_laser_dot.top_level = true
	_laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# We move the dot every render frame — physics interpolation would
	# smear it behind the actual aim point.
	_laser_dot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_laser_dot.visible = false
	add_child(_laser_dot)

	# Beam — ImmediateMesh line from muzzle proxy to hit point. Rebuilt
	# each frame in _update_laser since endpoints move.
	_laser_beam_im = ImmediateMesh.new()
	_laser_beam_mat = StandardMaterial3D.new()
	_laser_beam_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_laser_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_beam_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.55)
	_laser_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_beam_mat.disable_receive_shadows = true
	_laser_beam = MeshInstance3D.new()
	_laser_beam.mesh = _laser_beam_im
	_laser_beam.material_override = _laser_beam_mat
	_laser_beam.top_level = true
	_laser_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser_beam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_laser_beam.visible = false
	add_child(_laser_beam)

func _update_laser() -> void:
	if _laser_dot == null or _laser_beam == null:
		return
	var active: bool = _equipped and LASER_WEAPONS.has(_current_weapon) and _camera != null
	if active and _player != null and _player.has_method("is_menu_open") and _player.is_menu_open():
		active = false
	if active and _player != null and _player.has_method("is_pie_open") and _player.is_pie_open():
		active = false
	if not active:
		_laser_dot.visible = false
		_laser_beam.visible = false
		return
	# Use interpolated transform — camera has physics_interpolation on, so
	# global_transform lags the rendered view by up to one physics tick.
	var cam_xf: Transform3D = _camera.get_global_transform_interpolated()
	var origin: Vector3 = cam_xf.origin
	var basis: Basis = cam_xf.basis
	var fwd: Vector3 = -basis.z.normalized()
	var ads: bool = _player != null and _player.has_method("is_ads") and _player.is_ads()
	var offset: Vector3 = LASER_BEAM_OFFSET_ADS if ads else LASER_BEAM_OFFSET_HIP
	var muzzle: Vector3 = cam_xf * offset
	var end: Vector3 = origin + fwd * LASER_RANGE
	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(origin, end)
		var ex: Array[RID] = []
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r and r.has("position"):
			end = r.position
	_laser_dot.global_position = end
	_laser_dot.visible = true
	_laser_beam_im.clear_surfaces()
	_laser_beam_im.surface_begin(Mesh.PRIMITIVE_LINES, _laser_beam_mat)
	_laser_beam_im.surface_add_vertex(muzzle)
	_laser_beam_im.surface_add_vertex(end)
	_laser_beam_im.surface_end()
	_laser_beam.global_transform = Transform3D.IDENTITY
	_laser_beam.visible = true

# Recoil-control HUD getters. Returns the full pattern for the equipped weapon
# (so the panel can render the canonical climb path) and the current session
# telemetry — cumulative kick (rad), per-shot history, and live drift.
func get_recoil_pattern() -> Array:
	return _profile.get("recoil_pattern", []) if _equipped else []

func get_recoil_session() -> Dictionary:
	if not _equipped or _player == null:
		return {"active": false, "shots": 0, "kick_total": Vector2.ZERO, "drift": Vector2.ZERO, "history": []}
	var drift: Vector2 = _rec_frozen_drift if _rec_frozen else Vector2(
		_player._yaw - _rec_anchor_yaw, _player._pitch - _rec_anchor_pitch
	)
	return {
		"active": _rec_session_active,
		"shots": _rec_history.size(),
		"kick_total": _rec_kick_total,
		"drift": drift,
		"history": _rec_history,
	}
