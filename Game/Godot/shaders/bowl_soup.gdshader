shader_type canvas_item;
uniform float fullness : hint_range(0.0, 1.0) = 0.0;
uniform float slosh = 0.0;
uniform float ripple = 0.0;
uniform float clock_time = 0.0;
// Calibrated to the original 1312x1199 cauldron. The front rim remains opaque.
void fragment() {
	vec4 pot = texture(TEXTURE, UV);
	vec2 opening = (UV - vec2(0.500, 0.242)) / vec2(0.305, 0.143);
	float clip = 1.0 - smoothstep(0.970, 0.995, dot(opening, opening));
	// A full-width horizontal surface rises from below the front wall.
	// Perspective stays fixed; the opening mask reveals it as the level rises.
	// At zero the surface is entirely occluded, rather than a visible puddle.
	float depth = clamp(fullness/0.95, 0.0, 1.0);
	vec2 center = vec2(0.500, mix(0.526, 0.247, depth));
	vec2 radius = vec2(0.300, 0.139);
	vec2 q = UV - center;
	q.y -= slosh * q.x + sin(q.x*28.0 + clock_time*0.9)*0.0012*ripple;
	vec2 e = q / radius;
	float edge = dot(e,e);
	float mask = (1.0-smoothstep(0.96,1.0,edge))*clip*smoothstep(0.0,0.0003,fullness);
	// Muted opaque green, broad cloudy patches and a dark meniscus, not a glow.
	vec3 soup = mix(vec3(0.29,0.44,0.10),vec3(0.43,0.59,0.15),smoothstep(-0.8,0.8,e.y));
	float clouds = sin(e.x*6.5 + sin(e.y*4.7 + clock_time*0.15))
		* cos(e.y*5.6 - clock_time*0.11 + e.x*1.5);
	soup = mix(soup,vec3(0.51,0.62,0.22),smoothstep(-0.25,0.65,clouds)*0.32);
	float meniscus = smoothstep(0.82,0.94,edge);
	soup = mix(soup,vec3(0.22,0.34,0.07),meniscus*0.65);
	for (int i=0; i<3; i++) {
		float n = float(i);
		float phase = fract(clock_time/(4.8+n*0.55) + n*0.33);
		float inflate = smoothstep(0.10,0.70,phase);
		float visible = smoothstep(0.10,0.20,phase)*(1.0-smoothstep(0.77,0.82,phase));
		vec2 b = vec2(-0.48+n*0.45,0.08+sin(n*4.0)*0.26);
		vec2 delta = (e-b)*vec2(1.0,0.68);
		float d = length(delta);
		float r = (0.18+0.055*sin(n*2.0))*inflate*0.60;
		float spot = (1.0-smoothstep(r-0.008,r+0.008,d))*visible*smoothstep(0.06,0.18,fullness);
		float rim = smoothstep(r*0.70,r*0.98,d);
		vec3 dome = mix(vec3(0.52,0.66,0.22),vec3(0.24,0.38,0.08),rim);
		float highlight = 1.0-smoothstep(r*0.18,r*0.35,length(delta+vec2(r*0.30,r*0.26)));
		dome = mix(dome,vec3(0.65,0.75,0.34),highlight*0.60);
		soup = mix(soup,dome,spot);
		float after_pop = smoothstep(0.78,0.82,phase)*(1.0-smoothstep(0.82,0.97,phase));
		float wave_radius = r + (phase-0.8)*0.21;
		float ring = 1.0-smoothstep(0.0048,0.015,abs(d-wave_radius));
		soup = mix(soup,vec3(0.31,0.45,0.12),ring*after_pop*smoothstep(0.06,0.18,fullness)*0.55);
	}
	COLOR = vec4(mix(pot.rgb,soup,mask),pot.a);
}
