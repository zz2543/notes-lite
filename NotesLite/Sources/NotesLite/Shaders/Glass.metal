#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct GlassUniforms {
    float2 size;
    float2 sourceSize;
    float2 origin;
    float2 point;
    float elapsed;
    float dark;
    float strength;
    float reserved;
};
vertex VertexOut glassVertex(uint id [[vertex_id]]) {
    const float2 positions[] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 p = positions[id];
    return { float4(p,0,1), float2(p.x*.5+.5, .5-p.y*.5) };
}
fragment float4 glassFragment(VertexOut in [[stage_in]], constant GlassUniforms &u [[buffer(0)]], texture2d<float> backdrop [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 p = in.uv * u.size;
    float2 halfSize = u.size * .5;
    float radius = 20;
    float2 q = abs(p-halfSize) - (halfSize-radius);
    float distanceToEdge = length(max(q,0.0)) + min(max(q.x,q.y),0.0) - radius;
    float alpha = 1-smoothstep(-.5,1.0,distanceToEdge);
    float edge = exp(-abs(distanceToEdge)*.16);
    float2 normal = normalize((p-halfSize)/(halfSize*halfSize) + float2(.00001));
    float time = max(0.0,u.elapsed);
    float2 delta = p-u.point;
    float d = length(delta);
    float pulse = sin((d-time*260)*.075)*exp(-pow((d-time*260)/100,2.0))*exp(-time*4.8);
    float2 displacement = normal*edge*6 + normalize(delta+float2(.001))*pulse*7*u.strength;
    float2 uv = (u.origin+p+displacement)/max(u.sourceSize,float2(1));
    float3 color = float3(0);
    // A frosted, refracted sample of the actual window, not a procedural substitute.
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        color += backdrop.sample(s,uv+float2(x,y)*5/u.sourceSize).rgb/9;
    }
    float3 tint = mix(float3(.97,.97,.975),float3(.14,.14,.15),u.dark);
    color = mix(color,tint,.78);
    float light = dot(normal,normalize(float2(-.65,-1)))*.5+.5;
    color += edge*light*.17 + pulse*.018;
    color = clamp(color,0.0,1.0);
    return float4(color*alpha,alpha);
}
