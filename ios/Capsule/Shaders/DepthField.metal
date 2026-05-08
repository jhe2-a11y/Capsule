#include <metal_stdlib>
using namespace metal;

// Capsule depth-field renderer.
//
// Each memory is a billboarded textured quad placed in normalized capsule
// space (x,y in [-1,1], z in [0,1]). The "camera" is implied at z = 1.2; we
// project by perspective-divide on (1.2 - z). Foregrounded items are pulled
// toward z=1.0 by FocusController, others recede with depth-of-field blur.
//
// We do not draw chrome or text. Type is composed in SwiftUI overlays for
// readability; this renderer handles photo/video first frames, voice blobs,
// and the soft drop-shadow ambience that makes the field feel like a place.

struct VertexIn {
    float2 position;        // unit quad in [-0.5, 0.5]
    float2 uv;              // 0..1
};

struct InstanceIn {
    float3 worldPos;        // capsule-space position
    float2 sizePx;          // base size in points
    float  rotation;        // radians (subtle per-node tilt for life)
    float  alpha;           // fade for materialize-load
    float  blur;            // 0..1, used by fragment shader
    float  focus;           // 0..1, foreground emphasis
    float  kindFlag;        // 0=photo, 1=video, 2=voice, 3=text
    float  _pad;
};

struct CameraUniforms {
    float2 viewportSizePx;
    float2 parallaxOffset;  // radians of tilt → px offset
    float  zoomZ;           // dolly in z (additive to instance.worldPos.z)
    float  time;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float  alpha;
    float  blur;
    float  focus;
    float  kindFlag;
    float2 ndc;
};

vertex VertexOut depthfield_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant VertexIn*       verts     [[buffer(0)]],
    constant InstanceIn*     instances [[buffer(1)]],
    constant CameraUniforms& cam       [[buffer(2)]]
) {
    VertexIn  v = verts[vid];
    InstanceIn n = instances[iid];

    // Perspective by z: items closer to z=1 are larger.
    float z = clamp(n.worldPos.z + cam.zoomZ, 0.0, 0.99);
    float depth = 1.2 - z;                          // 0.21..1.20
    float scale = 1.0 / depth;                      // ~0.83..~4.76

    // Map normalized x,y (-1..1) to viewport px (with subtle parallax shift
    // weighted by 1-z so foreground moves more, background drifts less).
    float2 vp = cam.viewportSizePx;
    float  parallaxAmt = mix(0.4, 1.0, z);          // foreground reacts more
    float2 shift = cam.parallaxOffset * parallaxAmt;

    float2 center = float2(n.worldPos.x, n.worldPos.y) * (vp * 0.5);
    center += shift;

    // Local quad: rotate, then scale by node size and depth.
    float c = cos(n.rotation), s = sin(n.rotation);
    float2 local = float2(v.position.x * c - v.position.y * s,
                          v.position.x * s + v.position.y * c);
    local *= n.sizePx * scale;

    float2 pixel = center + local;
    float2 ndc = (pixel / (vp * 0.5));

    VertexOut out;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.uv       = v.uv;
    out.alpha    = n.alpha;
    out.blur     = n.blur;
    out.focus    = n.focus;
    out.kindFlag = n.kindFlag;
    out.ndc      = ndc;
    return out;
}

// Soft circular vignette inside the quad → cards feel like apertures, not rectangles.
inline float vignette(float2 uv) {
    float2 c = uv - 0.5;
    return smoothstep(0.55, 0.42, length(c));
}

// Cheap radial blur sample; real DoF is implemented at the SwiftUI layer for
// photo/video textures. Here we attenuate detail by alpha and desaturation.
fragment float4 depthfield_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float4 sample = tex.sample(s, in.uv);

    // Per-kind tinting (so kind is felt before read).
    float3 kindTint = float3(1.0);
    if (in.kindFlag > 1.5 && in.kindFlag < 2.5) {
        // voice: warm amber bias
        kindTint = float3(1.05, 0.96, 0.84);
    } else if (in.kindFlag > 2.5) {
        // text: cool ivory
        kindTint = float3(0.96, 0.96, 1.02);
    }

    float3 rgb = sample.rgb * kindTint;

    // Desaturate background nodes; saturate foreground.
    float gray = dot(rgb, float3(0.299, 0.587, 0.114));
    rgb = mix(float3(gray), rgb, mix(0.55, 1.05, in.focus));

    // Bloom on foregrounded item.
    float bloom = max(0.0, in.focus - 0.85) * 0.35;
    rgb += bloom;

    // Vignette aperture + fade with blur and alpha.
    float a = sample.a * vignette(in.uv) * in.alpha;
    a *= mix(0.7, 1.0, 1.0 - in.blur);

    return float4(rgb, a);
}
