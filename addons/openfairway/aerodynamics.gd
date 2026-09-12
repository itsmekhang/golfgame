class_name Aerodynamics
extends RefCounted
## GDScript port of OpenFairway `Aerodynamics.cs`.
## Air density, viscosity, and drag/lift coefficient helpers.

# Physical constants
const KELVIN_CELSIUS := 273.15
const PRESSURE_AT_SEALEVEL := 101325.0  # Pa
const EARTH_GRAVITY := 9.80665  # m/s²
const MOLAR_MASS_DRY_AIR := 0.0289644  # kg/mol
const UNIVERSAL_GAS_CONSTANT := 8.314462618  # J/(mol*K)
const GAS_CONSTANT_DRY_AIR := 287.058  # J/(kg*K)
const DYN_VISCOSITY_ZERO_DEGREE := 1.716e-05  # kg/(m*s)
const SUTHERLAND_CONSTANT := 198.72  # K (source: NASA)
const FEET_TO_METERS := 0.3048

const CL_MAX_BASE := 0.268
const CL_MAX_HIGH_SPIN := 0.32

var cl_max: float:
	get:
		return CL_MAX_BASE
var cl_max_high_spin: float:
	get:
		return CL_MAX_HIGH_SPIN
var cd_min: float:
	get:
		return FlightProfile.get_default().cd_min


static func fahrenheit_to_celsius(temp_f: float) -> float:
	return (temp_f - 32.0) * 5.0 / 9.0


## Air density in kg/m³ from altitude (ft or m) and temperature (F or C).
func get_air_density(altitude: float, temp: float, units: int) -> float:
	var temp_k: float
	var altitude_m: float
	if units == PhysicsEnums.Units.IMPERIAL:
		temp_k = fahrenheit_to_celsius(temp) + KELVIN_CELSIUS
		altitude_m = altitude * FEET_TO_METERS
	else:
		temp_k = temp + KELVIN_CELSIUS
		altitude_m = altitude

	# Barometric formula
	var exponent := (-EARTH_GRAVITY * MOLAR_MASS_DRY_AIR * altitude_m) / (UNIVERSAL_GAS_CONSTANT * temp_k)
	var pressure := PRESSURE_AT_SEALEVEL * exp(exponent)
	return pressure / (GAS_CONSTANT_DRY_AIR * temp_k)


## Dynamic viscosity in kg/(m*s) using Sutherland's formula.
func get_dynamic_viscosity(temp: float, units: int) -> float:
	var temp_k: float
	if units == PhysicsEnums.Units.IMPERIAL:
		temp_k = fahrenheit_to_celsius(temp) + KELVIN_CELSIUS
	else:
		temp_k = temp + KELVIN_CELSIUS
	return DYN_VISCOSITY_ZERO_DEGREE * pow(temp_k / KELVIN_CELSIUS, 1.5) * \
		(KELVIN_CELSIUS + SUTHERLAND_CONSTANT) / (temp_k + SUTHERLAND_CONSTANT)


func get_cd(re: float) -> float:
	return FlightAerodynamicsModel.get_cd(re)


func get_cl(re: float, spin_ratio: float) -> float:
	return FlightAerodynamicsModel.get_cl(re, spin_ratio)
