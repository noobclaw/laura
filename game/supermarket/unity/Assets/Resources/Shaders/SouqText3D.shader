// Lettering on signs inside the scene: drawn from the font's glyph picture, hidden by things in front of it.
Shader "Souq/Text3D"
{
    Properties { _MainTex ("Font", 2D) = "white" {} _Color ("Color", Color) = (1,1,1,1) }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
            CBUFFER_END
            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; };
            Varyings vert(Attributes i) { Varyings o; o.positionCS = TransformObjectToHClip(i.positionOS.xyz); o.uv = i.uv; o.color = i.color * _Color; return o; }
            half4 frag(Varyings i) : SV_Target { half a = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a; return half4(i.color.rgb, i.color.a * a); }
            ENDHLSL
        }
    }
}
