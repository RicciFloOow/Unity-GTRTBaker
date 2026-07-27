using UnityEngine;

namespace GTRTBaker
{
    public interface ISceneBakerLightFilter
    {
        bool IsValid(Light light);
    }
}