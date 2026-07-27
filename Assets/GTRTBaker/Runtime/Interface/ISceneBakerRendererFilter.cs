using UnityEngine;

namespace GTRTBaker
{
    public interface ISceneBakerRendererFilter
    {
        bool IsValid(Renderer renderer, out string reason);
    }
}