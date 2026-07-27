using UnityEngine;

namespace GTRTBaker
{
    public interface ILightDataConverter<T> where T : struct
    {
        T Convert(Light light);
    }
}