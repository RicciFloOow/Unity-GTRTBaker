using UnityEngine;

namespace GTRTBaker
{
    public class ReferencePTLightFilter : ISceneBakerLightFilter
    {
        public bool IsValid(Light light)
        {
            if (light == null) return false;

            return light.type == LightType.Directional || light.type == LightType.Point;
        }
    }
}