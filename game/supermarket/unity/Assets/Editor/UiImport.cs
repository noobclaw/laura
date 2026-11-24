// Interface pictures are kept uncompressed with clean edges; they are small and must stay sharp.
using UnityEditor;

public class UiImport : AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        if (!assetPath.Contains("/Resources/Ui/") && !assetPath.Contains("/Icon/")) return;
        var ti = (TextureImporter)assetImporter; ti.textureCompression = TextureImporterCompression.Uncompressed; ti.alphaIsTransparency = true; ti.mipmapEnabled = true; ti.npotScale = TextureImporterNPOTScale.None; ti.maxTextureSize = 1024; ti.wrapMode = UnityEngine.TextureWrapMode.Clamp;
    }
}
