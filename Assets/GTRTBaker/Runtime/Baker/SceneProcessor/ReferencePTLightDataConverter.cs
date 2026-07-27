using System.Runtime.InteropServices;
using UnityEngine;

namespace GTRTBaker
{
    [StructLayout(LayoutKind.Sequential)]
    public struct ReferencePTLightData
    {
        public Vector3 position;
        public uint type;//1: POINT_LIGHT, 2: DIRECTIONAL_LIGHT
        public Vector3 intensity;
        public uint pad;
    }

    public class ReferencePTLightDataConverter : ILightDataConverter<ReferencePTLightData>
    {
        public ReferencePTLightData Convert(Light light)
        {
            ReferencePTLightData data = new ReferencePTLightData();
            data.position = light.type == LightType.Directional ? -light.transform.forward : light.transform.position;
            data.type = light.type == LightType.Directional ? 2u : 1u;

            Color col = light.color * light.intensity;
            data.intensity = new Vector3(col.r, col.g, col.b);
            data.pad = 0;
            return data;
        }
    }
}