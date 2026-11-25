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
            RenderSettings.ambientSkyColor = new Color(0.56f, 0.49f, 0.42f);
            RenderSettings.ambientEquatorColor = new Color(0.44f, 0.35f, 0.28f);
            RenderSettings.ambientGroundColor = new Color(0.24f, 0.17f, 0.13f);
            try
            {
                var go = new GameObject("PostVolume");
                go.transform.SetParent(root, false);
                var vol = go.AddComponent<Volume>();
                vol.isGlobal = true;
                var p = ScriptableObject.CreateInstance<VolumeProfile>();
                vol.sharedProfile = p;
                var bloom = p.Add<Bloom>(true);
                bloom.threshold.value = 1.05f; bloom.intensity.value = 0.6f; bloom.scatter.value = 0.62f;
                bloom.tint.value = new Color(1f, 0.9f, 0.78f);
                var tone = p.Add<Tonemapping>(true);
                tone.mode.value = TonemappingMode.Neutral;
                var ca = p.Add<ColorAdjustments>(true);
                ca.postExposure.value = 0.15f; ca.contrast.value = 10f; ca.saturation.value = 8f;
                var wb = p.Add<WhiteBalance>(true);
                wb.temperature.value = 6f;
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
