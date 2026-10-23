#include <metal_stdlib>
using namespace metal;

struct MeshUniforms {
    float2 resolution;
    float time;
    float crossfadeProgress;
    float4 primaryColors[4];
    float4 secondaryColors[4];
};

// Точный Metal-шейдер HarmonoidMeshBackground (`src/components/HarmonoidMeshBackground.jsx` 1:1)
// 1. Заливка базы (`fillBase`: r = max(4, floor(c0.r * 0.35)), g = max(4, floor(c0.g * 0.35)), b = max(6, floor(c0.b * 0.40)))
// 2. 4 радиальных пятна (`speed = 0.45`, радиус `max(w, h) * (0.55 + 0.08 * sin(t * 0.35 + i))`):
//    - стопы градиента: 0.0 -> alpha 0.95, 0.45 -> alpha 0.45, 1.0 -> alpha 0.0
//    - пятно 0: source-over (mix)
//    - пятна 1..3: lighter (аддитивное сложение)
// 3. Внутреннее затемнение холста `rgba(0, 0, 0, 0.12)`
// 4. Внешняя виньетка `linear-gradient(180deg, rgba(0,0,0,0.22) 0%, transparent 20%, transparent 55%, rgba(0,0,0,0.28) 100%)`
// 5. Финальный слой `rgba(0, 0, 0, 0.18)`
fragment float4 harmonoidMeshFragment(
    float4 position [[position]],
    constant MeshUniforms &u [[buffer(0)]]
) {
    float2 uv = position.xy / max(u.resolution, float2(1.0));
    float w = u.resolution.x;
    float h = u.resolution.y;
    float maxDim = max(w, h);
    float t = u.time;

    float p = clamp(u.crossfadeProgress, 0.0, 1.0);
    float smoothT = p * p * (3.0 - 2.0 * p);

    float3 c0 = mix(u.primaryColors[0].rgb, u.secondaryColors[0].rgb, smoothT);
    float3 c1 = mix(u.primaryColors[1].rgb, u.secondaryColors[1].rgb, smoothT);
    float3 c2 = mix(u.primaryColors[2].rgb, u.secondaryColors[2].rgb, smoothT);
    float3 c3 = mix(u.primaryColors[3].rgb, u.secondaryColors[3].rgb, smoothT);

    // 1. fillBase: r = max(4/255, c0.r * 0.35), g = max(4/255, c0.g * 0.35), b = max(6/255, c0.b * 0.40)
    float3 color = float3(
        max(4.0 / 255.0, floor(c0.r * 255.0 * 0.35) / 255.0),
        max(4.0 / 255.0, floor(c0.g * 255.0 * 0.35) / 255.0),
        max(6.0 / 255.0, floor(c0.b * 255.0 * 0.40) / 255.0)
    );

    // 2. 4 control points (speed = 0.45)
    const float speed = 0.45;
    float2 p0 = float2((0.15 + sin(t * speed * 0.70 + 0.0) * 0.18) * w, (0.20 + cos(t * speed * 0.90 + 0.0 * 0.8) * 0.16) * h);
    float2 p1 = float2((0.85 + sin(t * speed * 0.85 + 1.3) * 0.16) * w, (0.18 + cos(t * speed * 1.10 + 1.3 * 0.8) * 0.20) * h);
    float2 p2 = float2((0.20 + sin(t * speed * 1.05 + 2.1) * 0.20) * w, (0.82 + cos(t * speed * 0.75 + 2.1 * 0.8) * 0.15) * h);
    float2 p3 = float2((0.82 + sin(t * speed * 0.95 + 3.4) * 0.17) * w, (0.85 + cos(t * speed * 1.00 + 3.4 * 0.8) * 0.18) * h);

    float2 centers[4] = { p0, p1, p2, p3 };
    float3 palette[4] = { c0, c1, c2, c3 };

    for (int i = 0; i < 4; ++i) {
        float radius = maxDim * (0.55 + 0.08 * sin(t * 0.35 + float(i)));
        float dist = distance(position.xy, centers[i]) / max(radius, 1.0);
        if (dist < 1.0) {
            // Stops: 0.0 -> 0.95, 0.45 -> 0.45, 1.0 -> 0.0
            float alpha = (dist < 0.45)
                ? mix(0.95, 0.45, dist / 0.45)
                : mix(0.45, 0.0, (dist - 0.45) / 0.55);

            if (i == 0) {
                // globalCompositeOperation = 'source-over'
                color = mix(color, palette[0], alpha);
            } else {
                // globalCompositeOperation = 'lighter'
                color = clamp(color + palette[i] * alpha, 0.0, 1.0);
            }
        }
    }

    // 3. Canvas 12% darkening: rgba(0, 0, 0, 0.12)
    color *= (1.0 - 0.12);

    // 4. Vertical vignette: 0% -> 0.22, 20% -> 0.0, 55% -> 0.0, 100% -> 0.28
    float vignetteAlpha = 0.0;
    if (uv.y < 0.20) {
        vignetteAlpha = mix(0.22, 0.0, uv.y / 0.20);
    } else if (uv.y > 0.55) {
        vignetteAlpha = mix(0.0, 0.28, (uv.y - 0.55) / 0.45);
    }
    color *= (1.0 - vignetteAlpha);

    // 5. Desktop Now Playing ambient overlay: rgba(0, 0, 0, 0.18)
    color *= (1.0 - 0.18);

    return float4(color, 1.0);
}
