using UnityEngine;

namespace GTRTBaker
{
    public interface IBakeStopStrategy
    {
        bool IsFinished(BakeContext context);
        float GetProgress(BakeContext context);
    }
}