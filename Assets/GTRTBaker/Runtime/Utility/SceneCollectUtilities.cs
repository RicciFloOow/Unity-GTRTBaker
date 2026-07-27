using System.Collections.Generic;
using UnityEngine;

namespace GTRTBaker
{
    public static class SceneCollectUtilities
    {
        #region ----Renderers----
        public enum AllowMaterialQueue
        {
            Opaque = 1,
            AlphaClip = 1 << 1,
            Transparent = 1 << 2,
            All = Opaque | AlphaClip | Transparent
        }

        public static List<Renderer> CollectAndProcessRenderers(ISceneBakerRendererProcessor processor, AllowMaterialQueue allowQueue = AllowMaterialQueue.Opaque)
        {
            if (processor == null)
            {
                Debug.LogError("The scene baker renderer processor is null!");
                return null;
            }

            Renderer[] allRenderers = Object.FindObjectsByType<Renderer>(
                FindObjectsInactive.Include, FindObjectsSortMode.None);

            List<Renderer> validRenderers = new List<Renderer>();

            foreach (var renderer in allRenderers)
            {
                if (IsValidRenderer(renderer, allowQueue))
                {
                    validRenderers.Add(renderer);
                    processor.Process(renderer);
                }
                else
                {
                    renderer.enabled = false;
                }
            }

            return validRenderers;
        }

        public static List<Renderer> CollectRenderers(ISceneBakerRendererFilter filter, bool logRejected = true)
        {
            if (filter == null)
            {
                Debug.LogError("The scene baker renderer filter is null!");
                return null;
            }

            Renderer[] allRenderers = Object.FindObjectsByType<Renderer>(FindObjectsInactive.Include, FindObjectsSortMode.None);

            List<Renderer> validRenderers = new List<Renderer>();

            foreach (var renderer in allRenderers)
            {
                if (filter.IsValid(renderer, out string reason))
                {
                    validRenderers.Add(renderer);
                }
                else if (logRejected && !string.IsNullOrEmpty(reason))
                {
                    Debug.LogWarning($"[GTRTBaker] renderer {renderer.gameObject.name} rejected: {reason}");
                }
            }

            return validRenderers;
        }

        private static bool IsValidRenderer(Renderer renderer, AllowMaterialQueue allowQueue = AllowMaterialQueue.Opaque)
        {
            if (!renderer.gameObject.activeInHierarchy || !renderer.enabled)
                return false;

            var materials = renderer.sharedMaterials;
            if (materials.Length == 0) return false;

            if (materials.Length > 32)
            {
                Debug.LogError($"[GTRTBaker] renderer {renderer.gameObject.name} contains {materials.Length} subMeshes，exceeding the DXR limit of 32 per instance. It will be excluded.");
                return false;
            }

            foreach (var mat in materials)
            {
                if (mat == null)
                {
                    Debug.LogError($"{renderer.gameObject} has missing or empty material!");
                    return false;
                }
                //@TODO: 用指定接口实现判断逻辑
                int queue = mat.renderQueue;
                AllowMaterialQueue currentMatQueueType;

                if (queue < 2450)
                {
                    currentMatQueueType = AllowMaterialQueue.Opaque;
                }
                else if (queue < 2500)
                {
                    currentMatQueueType = AllowMaterialQueue.AlphaClip;
                }
                else
                {
                    currentMatQueueType = AllowMaterialQueue.Transparent;
                }

                if ((allowQueue & currentMatQueueType) == 0)
                {
                    return false;
                }
            }

            return true;
        }
        #endregion

        #region ----Lights----
        public static List<Light> AnalyzeLightsWithChunks(Bounds sceneBounds, Vector3Int subdivisions, ISceneBakerLightFilter lightFilter, out List<int> flattenedLightIndices, out List<Vector2Int> chunkOffsets)
        {
            List<Light> validLights = AnalyzeLightsSimple(lightFilter);

            flattenedLightIndices = new List<int>();
            chunkOffsets = new List<Vector2Int>(subdivisions.x * subdivisions.y * subdivisions.z);

            Vector3 chunkSize = new Vector3(
                sceneBounds.size.x / subdivisions.x,
                sceneBounds.size.y / subdivisions.y,
                sceneBounds.size.z / subdivisions.z
            );

            for (int z = 0; z < subdivisions.z; z++)
            {
                for (int y = 0; y < subdivisions.y; y++)
                {
                    for (int x = 0; x < subdivisions.x; x++)
                    {
                        Vector3 chunkCenter = sceneBounds.min + new Vector3(
                            (x + 0.5f) * chunkSize.x,
                            (y + 0.5f) * chunkSize.y,
                            (z + 0.5f) * chunkSize.z
                        );
                        Bounds chunkBounds = new Bounds(chunkCenter, chunkSize);

                        int startIndex = flattenedLightIndices.Count;
                        int lightCount = 0;

                        for (int i = 0; i < validLights.Count; i++)
                        {
                            if (IsLightIntersectingChunk(validLights[i], chunkBounds))
                            {
                                flattenedLightIndices.Add(i);
                                lightCount++;
                            }
                        }

                        chunkOffsets.Add(new Vector2Int(startIndex, lightCount));
                    }
                }
            }

            return validLights;
        }

        public static List<Light> AnalyzeLightsSimple(ISceneBakerLightFilter lightFilter)
        {
            Light[] allLights = Object.FindObjectsByType<Light>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);

            List<Light> validLights = new List<Light>();
            foreach (var light in allLights)
            {
                if (light.enabled && light.gameObject.activeInHierarchy)
                {
                    if (lightFilter == null || lightFilter.IsValid(light))
                    {
                        validLights.Add(light);
                    }
                }
            }
            return validLights;
        }

        public static List<T> AnalyzeLightDatasWithChunks<T>(Bounds sceneBounds, Vector3Int subdivisions, ISceneBakerLightFilter lightFilter, ILightDataConverter<T> converter, out List<int> flattenedLightIndices, out List<Vector2Int> chunkOffsets) where T : struct
        {
            List<Light> validLights = AnalyzeLightsWithChunks(sceneBounds, subdivisions, lightFilter, out flattenedLightIndices, out chunkOffsets);

            List<T> lightDatas = new List<T>(validLights.Count);

            if (converter == null)
            {
                Debug.LogError("ILightDataConverter cannot be null!");
                return lightDatas;
            }

            for (int i = 0; i < validLights.Count; i++)
            {
                lightDatas.Add(converter.Convert(validLights[i]));
            }

            return lightDatas;
        }

        public static List<T> AnalyzeLightDatasSimple<T>(ISceneBakerLightFilter lightFilter, ILightDataConverter<T> converter) where T : struct
        {
            List<Light> validLights = AnalyzeLightsSimple(lightFilter);

            List<T> lightDatas = new List<T>(validLights.Count);

            if (converter == null)
            {
                Debug.LogError("ILightDataConverter cannot be null!");
                return lightDatas;
            }

            for (int i = 0; i < validLights.Count; i++)
            {
                lightDatas.Add(converter.Convert(validLights[i]));
            }

            return lightDatas;
        }

        private static bool IsLightIntersectingChunk(Light light, Bounds chunkBounds)
        {
            if (light.type == LightType.Directional) return true;

            float sqrDistance = SqDistPointAABB(light.transform.position, chunkBounds);
            return sqrDistance <= (light.range * light.range);
        }

        private static float SqDistPointAABB(Vector3 point, Bounds bounds)
        {
            float sqDist = 0.0f;
            Vector3 min = bounds.min;
            Vector3 max = bounds.max;

            for (int i = 0; i < 3; i++)
            {
                float v = point[i];
                if (v < min[i]) sqDist += (min[i] - v) * (min[i] - v);
                if (v > max[i]) sqDist += (v - max[i]) * (v - max[i]);
            }
            return sqDist;
        }
        #endregion
    }
}