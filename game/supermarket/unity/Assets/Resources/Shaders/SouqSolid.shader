// Vertex-coloured solids with soft wrapped light, sky fill, a thin rim and real shadows.
// No textures: every edge stays sharp at any screen size.
Shader "Souq/Solid"
{
    Properties { _Tint ("Tint", Color) = (1,1,1,1) _Glow ("Glow", Range(0,1)) = 0 }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                half _Glow;
            CBUFFER_END
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; half4 color : COLOR; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; half4 color : COLOR; };
            Varyings vert(Attributes i)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                o.color = i.color;
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                half3 n = normalize(i.normalWS);
                half3 v = normalize(GetWorldSpaceViewDir(i.positionWS));
                if (dot(n, v) < 0) n = -n;
                Light l = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half wrap = saturate(dot(n, l.direction) * 0.55 + 0.45);
                half shade = lerp(0.42, 1.0, l.shadowAttenuation);
                half3 hemi = lerp(half3(0.62, 0.60, 0.56), half3(0.88, 0.93, 1.0), n.y * 0.5 + 0.5);
                half3 albedo = i.color.rgb * _Tint.rgb;
                half3 lit = albedo * (hemi * 0.62 + l.color.rgb * wrap * 0.60 * shade);
                half rim = pow(1.0 - saturate(dot(n, v)), 3.0);
                lit += rim * 0.06 * half3(0.85, 0.93, 1.0);
                return half4(lerp(lit, albedo * 1.6, _Glow), 1);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                half _Glow;
            CBUFFER_END
            float3 _LightDirection;
            float4 vert(float4 positionOS : POSITION, float3 normalOS : NORMAL) : SV_POSITION
            {
                float3 ws = TransformObjectToWorld(positionOS.xyz);
                float3 n = TransformObjectToWorldNormal(normalOS);
                float4 cs = TransformWorldToHClip(ApplyShadowBias(ws, n, _LightDirection));
                #if UNITY_REVERSED_Z
                    cs.z = min(cs.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    cs.z = max(cs.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return cs;
            }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                half _Glow;
            CBUFFER_END
            float4 vert(float4 positionOS : POSITION) : SV_POSITION { return TransformObjectToHClip(positionOS.xyz); }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
    Fallback "Universal Render Pipeline/Unlit"
}
