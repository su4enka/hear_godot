shader_type spatial;
render_mode unshaded, cull_front, blend_mix, specular_disabled;

/* ===== ВКЛ/ВЫКЛ ===== */
uniform bool outline_enabled = true;

/* ===== ЦВЕТ/ПРОЗРАЧНОСТЬ ===== */
uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.2, 0.85);

/* ===== ТОЛЩИНА (МИР/ЭКРАН) ===== */
uniform bool  use_screen_space_width = true;   // ВКЛ: толщина в пикселях
uniform float outline_px = 2.0;                // толщина контура в px
uniform float width_base = 0.012;              // базовая (в мирах) — используется, когда use_screen_space_width=false
uniform float width_rim_gain = 0.0;
uniform float width_rim_power = 1.0;

/* Камера (для перевода px -> world) */
uniform vec3  camera_world_pos = vec3(0.0);
uniform bool  camera_is_ortho = false;
uniform float camera_fov_y_deg = 70.0;         // для perspective
uniform float camera_ortho_size = 10.0;        // для ortho (высота видимого объёма/2)
uniform float viewport_height_px = 720.0;      // высота экрана в пикселях

/* ===== СИЛУЭТ/ФИЛЬТРЫ ===== */
uniform float rim_thresh_inflate = 0.72;
uniform float rim_soft_inflate   = 0.10;
uniform float rim_thresh_visible = 0.72;
uniform float rim_soft_visible   = 0.10;

uniform vec3  world_up = vec3(0.0, 1.0, 0.0);
uniform float horiz_from = 0.55;
uniform float horiz_to   = 0.90;
uniform float horiz_strength = 1.0;

/* ===== АНТИ-З-ФАЙТ ===== */
uniform float view_push = 0.002;

varying float v_rim;

void vertex() {
    if (outline_enabled) {
        // позиция/нормаль в мире
        vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        vec3 Nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

        // камера (fallback в редакторе)
        vec3 cam = camera_world_pos;
        #ifdef CAMERA_POSITION
        if (length(cam) < 0.0001) { cam = CAMERA_POSITION; }
        #endif

        // фактор силуэта
        vec3 V = normalize(cam - world_pos);
        float ndotv = clamp(dot(Nw, V), 0.0, 1.0);
        float rim = 1.0 - ndotv;
        v_rim = rim;

        // подавление «горизонталей»
        float up_abs = abs(dot(Nw, normalize(world_up)));
        float horiz_mask = 1.0 - horiz_strength * smoothstep(horiz_from, horiz_to, up_abs);

        // допуск к экструзии
        float m_inflate = smoothstep(
            rim_thresh_inflate - rim_soft_inflate,
            rim_thresh_inflate + rim_soft_inflate, rim
        );

        // === вычисление толщины ===
        float width_world = width_base; // дефолт — мировая
        if (use_screen_space_width) {
            // перевод пикселей в мировые единицы для данного вертекса
            float dist = distance(cam, world_pos);
            if (camera_is_ortho) {
                // для ortho: высота видимой области = 2*camera_ortho_size
                float meters_per_pixel = (2.0 * camera_ortho_size) / max(viewport_height_px, 1.0);
                width_world = outline_px * meters_per_pixel;
            } else {
                // perspective: высота на дистанции dist = 2*dist*tan(fov/2)
                float fovy = radians(camera_fov_y_deg);
                float meters_per_pixel = (2.0 * dist * tan(fovy * 0.5)) / max(viewport_height_px, 1.0);
                width_world = outline_px * meters_per_pixel;
            }
        }

        // усиление к краю (по желанию)
        float rim_gain = pow(max(rim, 0.0), width_rim_power) * width_rim_gain;

        float width = (width_world + rim_gain) * m_inflate * horiz_mask;

        // экструзия + небольшой push
        VERTEX += NORMAL * (width + view_push * m_inflate);
    } else {
        v_rim = 0.0;
    }
}

void fragment() {
    if (!outline_enabled) { discard; }

    float m_vis = smoothstep(
        rim_thresh_visible - rim_soft_visible,
        rim_thresh_visible + rim_soft_visible, v_rim
    );
    if (m_vis <= 0.001) { discard; }

    ALBEDO = outline_color.rgb;
    ALPHA  = outline_color.a;
}
