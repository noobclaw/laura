// Soft contact shadow laid on the floor under people, fixtures and cars: a dark rounded patch that fades to nothing at its edge.
Shader "Souq/Blob"
{
    Properties { _Color ("Color", Color) = (0.05,0.07,0.16,0.34) }
    SubShader
    {
        Tags { "Queue" = "Transparent-20" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off Cull Off Offset -1, -1
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
            CBUFFER_END
            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes i) { Varyings o; o.positionCS = TransformObjectToHClip(i.positionOS.xyz); o.uv = i.uv * 2 - 1; return o; }
            half4 frag(Varyings i) : SV_Target
            {
                float2 q = max(abs(i.uv) - 0.45, 0); half d = saturate(length(q) / 0.55); half a = (1 - d) * (1 - d);
                return half4(_Color.rgb, _Color.a * a);
            }
            ENDHLSL
        }
    }
}
