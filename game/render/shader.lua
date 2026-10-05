-- render/shader.lua
-- Shadery GLSL dla grafiki 3D.
--  * chunk: bloki świata; światło nieba/bloków w kolorze wierzchołka,
--    pora dnia, mgła, przezroczystość "wycinana" (liście, rośliny)
--  * entity: moby, przedmioty, ramka zaznaczenia; macierz modelu + światło

local M = {}

local COMMON_VERTEX = [[
uniform mat4 u_proj;
uniform mat4 u_view;
uniform vec3 u_offset;
varying float v_dist;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 world = vec4(vertex_position.xyz + u_offset, 1.0);
  vec4 viewPos = u_view * world;
  v_dist = length(viewPos.xyz);
  return u_proj * viewPos;
}
]]

local CHUNK_PIXEL = [[
uniform float u_daylight;   // 0..1, jasność nieba (noc -> dzień)
uniform vec3 u_fogColor;
uniform float u_fogStart;
uniform float u_fogEnd;
uniform float u_alphaCut;   // próg odcięcia przezroczystości
varying float v_dist;

// Krzywa jasności jak w Minecraft Beta: l / (4 - 3l)
float curve(float l) {
  return mix(0.05, 1.0, l / (4.0 - 3.0 * l));
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 t = Texel(tex, uv);
  if (t.a < u_alphaCut) discard;
  float sky = curve(color.r * u_daylight);
  float blk = curve(color.g);
  vec3 light = max(vec3(sky), vec3(blk) * vec3(1.0, 0.92, 0.78));
  vec3 rgb = t.rgb * light * color.b;
  float fog = clamp((v_dist - u_fogStart) / (u_fogEnd - u_fogStart), 0.0, 1.0);
  rgb = mix(rgb, u_fogColor, fog);
  return vec4(rgb, t.a);
}
]]

local ENTITY_VERTEX = [[
uniform mat4 u_proj;
uniform mat4 u_view;
uniform mat4 u_model;
varying float v_dist;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 world = u_model * vec4(vertex_position.xyz, 1.0);
  vec4 viewPos = u_view * world;
  v_dist = length(viewPos.xyz);
  return u_proj * viewPos;
}
]]

local ENTITY_PIXEL = [[
uniform float u_light;      // jasność w miejscu bytu 0..1
uniform vec4 u_tint;        // np. czerwony błysk po trafieniu
uniform vec3 u_fogColor;
uniform float u_fogStart;
uniform float u_fogEnd;
varying float v_dist;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 t = Texel(tex, uv) * color;
  if (t.a < 0.1) discard;
  vec3 rgb = t.rgb * u_light;
  rgb = mix(rgb, u_tint.rgb, u_tint.a);
  float fog = clamp((v_dist - u_fogStart) / (u_fogEnd - u_fogStart), 0.0, 1.0);
  rgb = mix(rgb, u_fogColor, fog);
  return vec4(rgb, t.a);
}
]]

function M.load()
  M.chunk = love.graphics.newShader(CHUNK_PIXEL, COMMON_VERTEX)
  M.entity = love.graphics.newShader(ENTITY_PIXEL, ENTITY_VERTEX)
  M.entity:send("u_tint", { 0, 0, 0, 0 })
  M.entity:send("u_light", 1)
  return M
end

-- Wspólne uniformy kamery i mgły dla obu shaderów
function M.setCamera(proj, view, fogColor, fogStart, fogEnd)
  for _, s in ipairs({ M.chunk, M.entity }) do
    s:send("u_proj", "row", proj)
    s:send("u_view", "row", view)
    s:send("u_fogColor", fogColor)
    s:send("u_fogStart", fogStart)
    s:send("u_fogEnd", fogEnd)
  end
end

return M
