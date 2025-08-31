shader_type spatial;
render_mode unshaded, cull_front, blend_mix, specular_disabled;

/* ===== ВКЛ/ВЫКЛ ===== */
uniform bool outline_enabled = true;

/* ===== ЦВЕТ/ПРОЗРАЧНОСТЬ ===== */
uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.2, 0.85);

/* ===== ТОЛЩИНА ===== */
uniform float width_base = 0.012;      // базовая толщина
uniform float width_rim_gain = 0.0;    // добавка у силуэта
uniform float width_rim_power = 1.0;   // кривая роста к краю

/* ===== СИЛУЭТ: раздельные пороги ===== */
uniform float rim_thresh_inflate = 0.72;    // порог для ЭКСТРУЗИИ (vertex)
uniform float rim_soft_inflate   = 0.10;    // мягкость порога экструзии
uniform float rim_thresh_visible = 0.72;    // порог для ОТРИСОВКИ (fragment)
uniform float rim_soft_visible   = 0.10;    // мягкость порога отрисовки

/* ===== ПОДАВЛЕНИЕ «ГОРИЗОНТАЛЕЙ» ===== */
uniform vec3  world_up = vec3(0.0, 1.0, 0.0);
uniform float horiz_from = 0.55;
uniform float horiz_to   = 0.90;
uniform float horiz_strength = 1.0;

/* ===== АНТИ-З-ФАЙТ ===== */
uniform float view_push = 0.002;

/* varyings */
varying float v_rim;

void vertex() {
    if (outline_enabled) {
        // мировые
        vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        vec3 Nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

        // нормаль в ПРОСТРАНСТВЕ ВИДА
        vec3 Nv = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);

        // rim только по нормали: 0 — фронтально (|Nv.z|≈1), 1 — силуэт (Nv.z≈0)
        float rim = 1.0 - clamp(abs(Nv.z), 0.0, 1.0);
        v_rim = rim;

        // подавление «почти горизонтальных» (в world-space)
        float up_abs = abs(dot(Nw, normalize(world_up)));
        float horiz_mask = 1.0 - horiz_strength * smoothstep(horiz_from, horiz_to, up_abs);

        // допуск к экструзии
        float m_inflate = smoothstep(
            rim_thresh_inflate - rim_soft_inflate,
            rim_thresh_inflate + rim_soft_inflate, rim
        );

        // толщина
        float rim_gain = pow(max(rim, 0.0), width_rim_power) * width_rim_gain;
        float width = (width_base + rim_gain) * m_inflate * horiz_mask;

        // экструзия + микропуш
        VERTEX += NORMAL * (width + view_push * m_inflate);
    } else {
        v_rim = 0.0;
    }
}

void fragment() {
    if (!outline_enabled) {
        discard;
    }

    // видимость по силуэту
    float m_vis = smoothstep(
        rim_thresh_visible - rim_soft_visible,
        rim_thresh_visible + rim_soft_visible, v_rim
    );
    if (m_vis <= 0.001) {
        discard;
    }

    ALBEDO = outline_color.rgb;
    ALPHA  = outline_color.a;
}
