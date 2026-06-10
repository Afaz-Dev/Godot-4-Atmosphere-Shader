
// More realistic atmosphere model, based on Sebastian Lague's Coding Adventure.

#include "atmosphere_common.gdshaderinc"
#include "util.gdshaderinc"

uniform sampler2D u_optical_depth_texture : repeat_disable;
uniform float u_scattering_strength = 30.0;
uniform vec3 u_scattering_wavelengths = vec3(700.0, 530.0, 440.0);
uniform vec3 u_atmosphere_modulate : source_color = vec3(1.0);
uniform vec3 u_atmosphere_ambient_color : source_color = vec3(0.0, 0.0, 0.002);

//Afaz's
uniform float u_horizon_boost = 1.7;

float get_baked_optical_depth(
	vec3 pos,
	vec3 dir,
	vec3 planet_center,
	sampler2D optical_depth_texture,
) {
	float height = distance(pos, planet_center) - u_planet_radius; //Zylann original
	//float height = length(pos) - u_planet_radius; Afaz modified
	float height_ratio = clamp(height / u_atmosphere_height, 0.0, 1.0);
	vec3 up = normalize(pos - planet_center);
	float uvx = 0.5 + 0.5 * dot(up, dir);

	// TODO Account for samples taken below planet surface
	// they can be added as a linear equation since density is constant

	return texture(optical_depth_texture, vec2(uvx, height_ratio)).r;
}

// Returns RGBA
vec4 compute_atmosphere_v2(
	vec3 ray_origin,
	vec3 ray_dir,
	vec3 planet_center, // with afaz's modification, it will now always be vec3(0)
	float t_begin,
	float t_end,
	float linear_depth,
	vec3 sun_dir,
	float jitter
) {
	// Rocky planets don't need many steps (8 can be enough).
	// However gas giants need a lot more (64?) since rays traverse it fully.
	const int steps = ATMOSPHERE_RAYMARCH_STEPS;

	// TODO Compute this in script?
	vec3 scattering_coefficients = vec3(
		pow4(400.0 / u_scattering_wavelengths.x),
		pow4(400.0 / u_scattering_wavelengths.y),
		pow4(400.0 / u_scattering_wavelengths.z)
	) * u_scattering_strength;

	float step_len = (t_end - t_begin) / float(steps);
	vec3 total_light = vec3(0.0);
	float view_ray_optical_depth = 0.0;
	float alpha = 0.0;
	vec3 pos0 = ray_origin + ray_dir * t_begin;
	vec3 pos = pos0;

	for (int i = 0; i < steps; ++i) {
		float sun_ray_optical_depth =
			get_baked_optical_depth(pos, sun_dir, planet_center, u_optical_depth_texture);

		float height = distance(pos, planet_center); //Zylann original
		//float height = length(pos) Afaz modified
		float local_density = get_atmosphere_density(height) * u_density;
		view_ray_optical_depth += local_density * step_len;
//		view_ray_optical_depth =
//			get_baked_optical_depth(pos0, ray_dir, planet_center, u_optical_depth_texture)
//			- get_baked_optical_depth(pos, ray_dir, planet_center, u_optical_depth_texture);

		vec3 transmittance = exp(
			-(sun_ray_optical_depth + view_ray_optical_depth)
			* scattering_coefficients);
		
		
		// Some modifications (By Afaz)
		// the goal here is to increase the terminator's scatter
		float mu = dot(ray_dir, sun_dir);
		
		// Shift terminator slightly
		mu = mu * 0.9 + 0.1;
		
		// Horizon boost (this is where i widen the terminator)
		float horizon = u_horizon_boost - abs(mu);
		
		// Smooth shaping (for stability into Godot 4 HDR)
		horizon = pow(horizon, 2.5);
		
		// Add controlled boost
		float phase_boost = 1.0 + horizon * 2.5;
		
		total_light += local_density * step_len * transmittance * scattering_coefficients * phase_boost;
		// end of modifications

		// Alpha depends on the amount of stuff the ray goes through
		float vtransmittance = exp(-local_density * step_len);
		alpha += (1.0 - vtransmittance) * (1.0 - alpha);

		pos += ray_dir * step_len;
	}

//	float sunp = dot(ray_dir, sun_dir);
//	total_light += vec3(1.0) * pow(max(sunp, 0.0), 20.0);

	// Former alpha calculation, causing the atmosphere to stop drawing the darker it gets
//	alpha = clamp(max(max(total_light.r, total_light.g), total_light.b), 0.0, 1.0);
//	alpha = sqrt(alpha);

	total_light = clamp(total_light + u_atmosphere_ambient_color, vec3(0.0), vec3(1.0));

	// Get rid of color banding.
	// Make sure it doesn't go out of bounds.
	// Also for some reason clamping to 1.0 caused HDR sunsets to be noisy
	alpha = clamp(alpha + jitter * 0.02, 0.0, 0.99);

	total_light *= u_atmosphere_modulate;

	return vec4(total_light, alpha);
}
