// 別吃壽司 - 整體觀感：環境光、後期處理（泛光、調色、暗角）。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace DontEatSushi
{
    public static class Look
    {
        public static void Apply(Camera cam, Transform root)
        {
            // 上方暖白、側面暖棕、下方深棕的三色環境光，取代單一顏色
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.92f, 0.84f, 0.72f);
            RenderSettings.ambientEquatorColor = new Color(0.70f, 0.56f, 0.44f);
            RenderSettings.ambientGroundColor = new Color(0.36f, 0.25f, 0.19f);
            try
            {
                var go = new GameObject("PostVolume");
                go.transform.SetParent(root, false);
                var vol = go.AddComponent<Volume>();
                vol.isGlobal = true;
                var p = ScriptableObject.CreateInstance<VolumeProfile>();
                vol.sharedProfile = p;
                var bloom = p.Add<Bloom>(true);
                bloom.threshold.value = 1.0f; bloom.intensity.value = 0.85f; bloom.scatter.value = 0.68f;
                bloom.tint.value = new Color(1f, 0.9f, 0.78f);
                var tone = p.Add<Tonemapping>(true);
                tone.mode.value = TonemappingMode.Neutral;
                var ca = p.Add<ColorAdjustments>(true);
                ca.postExposure.value = -0.05f; ca.contrast.value = 12f; ca.saturation.value = 14f;
                var wb = p.Add<WhiteBalance>(true);
                wb.temperature.value = 10f;
                var vg = p.Add<Vignette>(true);
                vg.intensity.value = 0.30f; vg.smoothness.value = 0.55f; vg.color.value = new Color(0.10f, 0.05f, 0.03f);
                var data = cam.GetUniversalAdditionalCameraData();
                data.renderPostProcessing = true;
                data.antialiasing = AntialiasingMode.FastApproximateAntialiasing;
            }
            catch (System.Exception e)
            {
                Debug.LogWarning("Look: post-processing unavailable: " + e.Message);
            }
        }
    }
}
